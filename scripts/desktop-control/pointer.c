#include <wayland-client.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "wlr-virtual-pointer-unstable-v1-client-protocol.h"

struct state {
  const char *name;
  struct zwlr_virtual_pointer_manager_v1 *manager;
  struct wl_output *output;
};

static void output_name(void *data, struct wl_output *output, const char *name) {
  struct state *state = data;
  if (strcmp(name, state->name) == 0) state->output = output;
}

static void output_geometry(void *data, struct wl_output *output, int32_t x, int32_t y,
                            int32_t physical_width, int32_t physical_height, int32_t subpixel,
                            const char *make, const char *model, int32_t transform) {}
static void output_mode(void *data, struct wl_output *output, uint32_t flags,
                        int32_t width, int32_t height, int32_t refresh) {}
static void output_done(void *data, struct wl_output *output) {}
static void output_scale(void *data, struct wl_output *output, int32_t factor) {}
static void output_description(void *data, struct wl_output *output, const char *description) {}

static const struct wl_output_listener output_listener = {
  .geometry = output_geometry,
  .mode = output_mode,
  .done = output_done,
  .scale = output_scale,
  .name = output_name,
  .description = output_description,
};

static void global(void *data, struct wl_registry *registry, uint32_t id,
                   const char *interface, uint32_t version) {
  struct state *state = data;
  if (strcmp(interface, zwlr_virtual_pointer_manager_v1_interface.name) == 0 && version >= 2) {
    state->manager = wl_registry_bind(registry, id, &zwlr_virtual_pointer_manager_v1_interface, 2);
  } else if (strcmp(interface, wl_output_interface.name) == 0 && version >= 4) {
    struct wl_output *output = wl_registry_bind(registry, id, &wl_output_interface, 4);
    wl_output_add_listener(output, &output_listener, state);
  }
}

static const struct wl_registry_listener registry_listener = { .global = global };

static uint32_t number(const char *value) {
  char *end;
  unsigned long result = strtoul(value, &end, 10);
  if (end == value || *end || result > UINT32_MAX) exit(2);
  return (uint32_t)result;
}

int main(int argc, char **argv) {
  if (argc != 6) return 2;
  uint32_t x = number(argv[2]), y = number(argv[3]);
  uint32_t width = number(argv[4]), height = number(argv[5]);
  if (!width || !height || x >= width || y >= height) return 2;

  struct state state = { .name = argv[1] };
  struct wl_display *display = wl_display_connect(NULL);
  if (!display) return 3;
  struct wl_registry *registry = wl_display_get_registry(display);
  wl_registry_add_listener(registry, &registry_listener, &state);
  wl_display_roundtrip(display);
  wl_display_roundtrip(display);
  if (!state.manager || !state.output) return 4;

  struct zwlr_virtual_pointer_v1 *pointer =
    zwlr_virtual_pointer_manager_v1_create_virtual_pointer_with_output(state.manager, NULL, state.output);
  zwlr_virtual_pointer_v1_motion_absolute(pointer, 0, x, y, width, height);
  zwlr_virtual_pointer_v1_frame(pointer);
  int result = wl_display_roundtrip(display);
  zwlr_virtual_pointer_v1_destroy(pointer);
  wl_display_disconnect(display);
  return result < 0 ? 5 : 0;
}
