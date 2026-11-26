#include <gio/gio.h>
#include <stdlib.h>
#include <string.h>

__attribute__((constructor))
static void keep_screencast_bus(int argc, char **argv) {
    if (!getenv("WAYLAND_DISPLAY") || !getenv("DBUS_SESSION_BUS_ADDRESS")) {
        return;
    }

    // Only the browser process opens screen cast portal sessions.
    for (int i = 1; i < argc; i++) {
        if (strncmp(argv[i], "--type=", 7) == 0) {
            return;
        }
    }

    // GIO caches the shared session connection weakly. Holding a reference
    // across the preview and capture proxies lets the portal recognize the
    // same sender when the browser presents its single-use restore token.
    GDBusConnection *connection = g_bus_get_sync(G_BUS_TYPE_SESSION, NULL, NULL);
    if (connection != NULL) {
        g_dbus_connection_set_exit_on_close(connection, FALSE);
        g_signal_connect_swapped(connection, "closed", G_CALLBACK(g_object_unref), connection);
    }
}
