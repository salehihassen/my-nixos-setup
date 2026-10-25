"""Regression checks for dictation lifecycle; no desktop, microphone or network."""
import asyncio
import importlib.util
import os
from pathlib import Path
import socket
import tempfile
import sys
from types import SimpleNamespace
import unittest
from unittest.mock import AsyncMock, patch

sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("dictation", Path(__file__).with_name("dictation.py"))
dictation = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dictation)


class DictationTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.runtime = Path(self.temporary.name) / "dictation"
        self.runtime.mkdir()
        self.config = {
            "systemctl": "systemctl", "notify": "notify-send", "niri": "niri",
            "voxtype": "voxtype", "wtype": "wtype", "wlCopy": "wl-copy",
            "niriIntegration": True, "recordingLimit": 300, "polishTimeout": 45,
            "polishModel": "llama3.2:3b",
        }
        self.controller = dictation.Controller(self.config, self.runtime)
        self.controller.systemctl = AsyncMock(return_value=("", 0))
        self.controller.notify = AsyncMock()

    async def asyncTearDown(self):
        worker = self.controller.worker
        if worker and not worker.done():
            worker.cancel()
            try:
                await worker
            except asyncio.CancelledError:
                pass
        self.controller.events.close()
        self.temporary.cleanup()

    async def session(self, mode, text="  A faithful\n transcript. ", preparation_error=None):
        self.controller.prepare_voxtype = AsyncMock()
        self.controller.prepare_ollama = AsyncMock(side_effect=preparation_error)
        self.controller.deliver = AsyncMock()
        self.controller.busy = {"voxtype"} | ({"ollama"} if mode == "polished" else set())

        async def state(states, *args, **kwargs):
            if "recording" in states:
                return "recording"
            next(self.runtime.glob("session-*" )).joinpath("transcript.txt").write_text(text)
            return "idle"

        with patch.object(self.controller.events, "wait", AsyncMock(side_effect=state)), \
             patch.object(dictation, "command", AsyncMock(return_value=("", 0))):
            await self.controller.session(mode, 42)

    async def test_faithful_never_starts_ollama_and_cleans_transcript(self):
        await self.session("faithful")
        self.controller.prepare_ollama.assert_not_awaited()
        self.controller.deliver.assert_awaited_once_with("A faithful transcript.", 42)
        self.assertFalse(list(self.runtime.glob("session-*")))
        self.assertEqual(self.controller.busy, set())
        self.controller.systemctl.assert_awaited_once_with("restart", "dictation-voxtype-idle.timer")

    async def test_polish_timeout_falls_back_to_faithful(self):
        self.controller.polish = AsyncMock(side_effect=asyncio.TimeoutError)
        await self.session("polished")
        self.controller.deliver.assert_awaited_once_with("A faithful transcript.", 42)
        self.assertEqual(self.controller.phase, "idle")
        self.assertEqual(self.controller.busy, set())

    async def test_malformed_cleanup_response_falls_back(self):
        with patch.object(dictation, "api", AsyncMock(return_value={"message": {"content": None}})):
            await self.session("polished")
        self.controller.deliver.assert_awaited_once_with("A faithful transcript.", 42)

    async def test_empty_cleanup_response_falls_back(self):
        with patch.object(dictation, "api", AsyncMock(return_value={"message": {"content": " "}})):
            await self.session("polished")
        self.controller.deliver.assert_awaited_once_with("A faithful transcript.", 42)

    async def test_unavailable_polish_model_still_dictates(self):
        self.controller.polish = AsyncMock()
        await self.session("polished", preparation_error=OSError("Unavailable"))
        self.controller.polish.assert_not_awaited()
        self.controller.deliver.assert_awaited_once_with("A faithful transcript.", 42)

    async def test_silence_does_not_type(self):
        await self.session("faithful", " \n ")
        self.controller.deliver.assert_not_awaited()
        self.assertFalse(list(self.runtime.glob("session-*")))

    async def test_same_window_types_once_without_enter(self):
        self.controller.focus = AsyncMock(return_value=42)
        with patch.object(dictation, "command", AsyncMock(return_value=("", 0))) as run:
            await self.controller.deliver("hello", 42)
        run.assert_awaited_once_with("wtype", "-", data=b"hello", check=False)

    async def test_changed_or_unknown_focus_uses_clipboard(self):
        for starting, current in ((42, 43), (42, None), (None, None)):
            self.controller.focus = AsyncMock(return_value=current)
            with patch.object(dictation, "command", AsyncMock(return_value=("", 0))) as run:
                await self.controller.deliver("hello", starting)
            self.assertEqual(run.call_args.args[0], "wl-copy")

    async def test_failed_typing_falls_back_without_typing_again(self):
        self.controller.focus = AsyncMock(return_value=42)
        with patch.object(dictation, "command", AsyncMock(side_effect=[("", 1), ("", 0)])) as run:
            await self.controller.deliver("hello", 42)
        self.assertEqual([call.args[0] for call in run.await_args_list], ["wtype", "wl-copy"])

    async def test_timer_cannot_unload_a_busy_component(self):
        self.controller.busy.add("voxtype")
        self.controller.loaded.add("voxtype")
        self.assertEqual(await self.controller.handle({"action": "idle", "component": "voxtype"}), "busy")
        self.controller.systemctl.assert_not_awaited()
        self.assertIn("voxtype", self.controller.loaded)

    async def test_idle_unloads_then_stops_only_dedicated_ollama(self):
        self.controller.loaded.update({"ollama", "voxtype"})
        with patch.object(dictation, "api", AsyncMock()) as api:
            await self.controller.handle({"action": "idle", "component": "ollama"})
        self.assertEqual(api.call_args.args[2]["keep_alive"], 0)
        self.controller.systemctl.assert_awaited_once_with("stop", "ollama.service", check=False)
        self.assertEqual(self.controller.loaded, {"voxtype"})

    async def test_expiring_shutdown_does_not_kill_new_request(self):
        self.controller.phase = "preparing"
        self.controller.busy.add("voxtype")
        self.controller.finish_if_idle()
        self.assertFalse(self.controller.finished.is_set())

    async def test_repeated_request_cancels_relevant_idle_timer(self):
        self.controller.focus = AsyncMock(return_value=42)
        pending = asyncio.Event()
        async def wait(*args):
            await pending.wait()
        self.controller.session = wait
        await self.controller.handle({"action": "toggle", "mode": "faithful"})
        self.controller.systemctl.assert_awaited_once_with("stop", "dictation-voxtype-idle.timer", check=False)
        self.assertEqual(self.controller.busy, {"voxtype"})

    async def test_cancel_during_preparation_discards_result_and_releases_resources(self):
        began = asyncio.Event()
        async def prepare():
            began.set()
            await asyncio.Event().wait()
        self.controller.prepare_voxtype = prepare
        self.controller.focus = AsyncMock(return_value=42)
        self.controller.deliver = AsyncMock()
        await self.controller.handle({"action": "toggle", "mode": "polished"})
        await began.wait()
        await self.controller.handle({"action": "cancel"})
        self.controller.deliver.assert_not_awaited()
        self.assertEqual(self.controller.phase, "idle")
        self.assertEqual(self.controller.busy, set())
        self.assertFalse(list(self.runtime.glob("session-*")))
        stops = [call.args for call in self.controller.systemctl.await_args_list if call.args[0] == "stop"]
        self.assertIn(("stop", "voxtype.service"), stops)
        self.assertIn(("stop", "ollama.service"), stops)

    async def test_cancel_before_worker_starts_is_reusable(self):
        self.controller.focus = AsyncMock(return_value=42)
        await self.controller.handle({"action": "toggle", "mode": "faithful"})
        await self.controller.handle({"action": "cancel"})
        self.assertEqual(self.controller.phase, "idle")
        self.assertEqual(self.controller.busy, set())
        self.assertFalse(list(self.runtime.glob("session-*")))

    async def test_state_events_observe_real_close_and_atomic_rename(self):
        revision = self.controller.events.revision
        waiter = asyncio.create_task(self.controller.events.wait({"recording"}, 2, after=revision))
        state = self.controller.events.directory / "state"
        state.write_text("recording")
        self.assertEqual(await waiter, "recording")
        revision = self.controller.events.revision
        temporary = state.with_suffix(".new")
        temporary.write_text("idle")
        temporary.rename(state)
        self.assertEqual(await self.controller.events.wait({"idle"}, 2, after=revision), "idle")

    async def test_socket_survives_controller_exit_for_next_activation(self):
        path = self.runtime / "activation.sock"
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as listener:
            listener.bind(str(path))
            listener.listen()
            inherited = listener.dup()
            self.controller.finished.set()
            with patch.dict(os.environ, {"LISTEN_FDS": "1", "LISTEN_PID": str(os.getpid())}), \
                 patch.object(dictation, "socket", SimpleNamespace(socket=lambda **kwargs: inherited)), \
                 patch.object(asyncio.get_running_loop(), "add_signal_handler"):
                await self.controller.run()
            self.assertTrue(path.exists())
            with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
                client.settimeout(1)
                client.connect(str(path))
                accepted, _ = listener.accept()
                accepted.close()

    def test_normalize_never_leaves_newlines_or_control_characters(self):
        self.assertEqual(dictation.normalize("Hello\r\nworld.\t\x1b\x00"), "Hello world.")


if __name__ == "__main__":
    unittest.main()
