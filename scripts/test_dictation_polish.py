"""Optional semantic checks against local Ollama; synthetic text, no capture or typing."""
import argparse
import asyncio
from pathlib import Path
import re
import tempfile

from dictation import Controller, normalize


# Keep these examples out of the prompt: they test generalization, not recall.
CASES = (
    (
        "correction across sentences preserves the earlier request",
        "Let's delete files A, B, and C, and let's read out the contents of D. "
        "Oh wait, actually let's read out the contents of file E, please print that.",
        {"delete", "a", "b", "c", "read", "contents", "e"}, {"d", "oh", "wait", "actually"},
    ),
    (
        "unfinished list is not completed",
        "let's delete file A, B, and \t and let's read out the contents of D. "
        "Oh wait, actually let's read out the contents of file E, please print that.",
        {"delete", "a", "b", "read", "contents", "e"}, {"c", "d", "oh", "wait", "actually"},
    ),
    (
        "recipient correction preserves the separate backup request",
        "Keep the backup. Send the summary to Maya. Oh wait, actually send the summary to Omar, please do that.",
        {"keep", "backup", "send", "summary", "omar"}, {"maya", "oh", "wait", "actually"},
    ),
    (
        "earlier negation survives a later correction",
        "Don't delete file A. Read the contents of D. Oh wait, actually read the contents of E.",
        {"don't", "delete", "a", "read", "contents", "e"}, {"d", "oh", "wait", "actually"},
    ),
    (
        "two independent choices are both retained",
        "Read file D and read file E.",
        {"read", "d", "and", "e"}, set(),
    ),
    (
        "short correction still works",
        "Delete files A, B, and C. And let's print out file D, actually let's print out file E.",
        {"delete", "a", "b", "c", "print", "e"}, {"d", "actually"},
    ),
)


async def check(config):
    failures = 0
    with tempfile.TemporaryDirectory(prefix="dictation-polish-tests-") as directory:
        controller = Controller(config, Path(directory) / "dictation")
        try:
            for name, source, required, forbidden in CASES:
                try:
                    result = await controller.polish(normalize(source))
                    words = set(re.findall(r"\w+(?:['’]\w+)*", result.casefold()))
                    passed = required <= words and not forbidden & words
                except (OSError, ValueError, RuntimeError, asyncio.TimeoutError):
                    passed = False
                print(f"{'PASS' if passed else 'FAIL'}: {name}", flush=True)
                failures += not passed
        finally:
            controller.events.close()
    return bool(failures)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--url", default="http://127.0.0.1:11435")
    parser.add_argument("--model", default="llama3.2:3b")
    parser.add_argument("--timeout", type=int, default=45)
    args = parser.parse_args()
    raise SystemExit(asyncio.run(check({
        "ollamaUrl": args.url, "polishModel": args.model, "polishTimeout": args.timeout,
    })))
