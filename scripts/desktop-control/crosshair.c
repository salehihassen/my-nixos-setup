#include <gtk/gtk.h>
#include <gtk4-layer-shell.h>
#include <cairo.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void draw(GtkDrawingArea *area, cairo_t *cr, int width, int height, gpointer data) {
  double *point = data;
  double x = point[0], y = point[1];
  (void)area; (void)width; (void)height;

  cairo_set_line_width(cr, 5);
  cairo_set_source_rgba(cr, 0, 0, 0, 0.85);
  cairo_arc(cr, x, y, 15, 0, 2 * G_PI);
  cairo_stroke_preserve(cr);
  cairo_set_line_width(cr, 3);
  cairo_set_source_rgb(cr, 1, 0.25, 0.25);
  cairo_stroke(cr);

  cairo_set_line_width(cr, 3);
  cairo_set_source_rgb(cr, 1, 1, 1);
  cairo_move_to(cr, x - 32, y); cairo_line_to(cr, x - 19, y);
  cairo_move_to(cr, x + 19, y); cairo_line_to(cr, x + 32, y);
  cairo_move_to(cr, x, y - 32); cairo_line_to(cr, x, y - 19);
  cairo_move_to(cr, x, y + 19); cairo_line_to(cr, x, y + 32);
  cairo_stroke(cr);
}

static gboolean ready(gpointer unused) {
  (void)unused;
  puts("READY");
  fflush(stdout);
  return G_SOURCE_REMOVE;
}

int main(int argc, char **argv) {
  if (argc != 4) return 2;
  char *end_x, *end_y;
  long x = strtol(argv[2], &end_x, 10), y = strtol(argv[3], &end_y, 10);
  if (*end_x || *end_y || x < 0 || y < 0) return 2;

  gtk_init();
  GdkDisplay *display = gdk_display_get_default();
  if (!display || !gtk_layer_is_supported()) return 3;
  GListModel *monitors = gdk_display_get_monitors(display);
  GdkMonitor *monitor = NULL;
  for (guint i = 0; i < g_list_model_get_n_items(monitors); i++) {
    GdkMonitor *candidate = g_list_model_get_item(monitors, i);
    const char *connector = gdk_monitor_get_connector(candidate);
    if (connector && strcmp(connector, argv[1]) == 0) {
      monitor = candidate;
      break;
    }
    g_object_unref(candidate);
  }
  if (!monitor) return 4;

  GdkRectangle geometry;
  gdk_monitor_get_geometry(monitor, &geometry);
  if (x >= geometry.width || y >= geometry.height) return 5;
  const int size = 72;
  int left = CLAMP((int)x - size / 2, 0, MAX(0, geometry.width - size));
  int top = CLAMP((int)y - size / 2, 0, MAX(0, geometry.height - size));
  double point[2] = { x - left, y - top };

  GtkCssProvider *css = gtk_css_provider_new();
  gtk_css_provider_load_from_string(css, "window.crosshair { background: transparent; box-shadow: none; }");
  gtk_style_context_add_provider_for_display(display, GTK_STYLE_PROVIDER(css), GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);
  g_object_unref(css);

  GtkWindow *window = GTK_WINDOW(gtk_window_new());
  gtk_widget_add_css_class(GTK_WIDGET(window), "crosshair");
  gtk_window_set_decorated(window, FALSE);
  gtk_window_set_default_size(window, size, size);
  gtk_layer_init_for_window(window);
  gtk_layer_set_namespace(window, "desktop-control-crosshair");
  gtk_layer_set_layer(window, GTK_LAYER_SHELL_LAYER_OVERLAY);
  gtk_layer_set_keyboard_mode(window, GTK_LAYER_SHELL_KEYBOARD_MODE_NONE);
  gtk_layer_set_exclusive_zone(window, 0);
  gtk_layer_set_monitor(window, monitor);
  gtk_layer_set_anchor(window, GTK_LAYER_SHELL_EDGE_LEFT, TRUE);
  gtk_layer_set_anchor(window, GTK_LAYER_SHELL_EDGE_TOP, TRUE);
  gtk_layer_set_margin(window, GTK_LAYER_SHELL_EDGE_LEFT, left);
  gtk_layer_set_margin(window, GTK_LAYER_SHELL_EDGE_TOP, top);

  GtkWidget *canvas = gtk_drawing_area_new();
  gtk_drawing_area_set_draw_func(GTK_DRAWING_AREA(canvas), draw, point, NULL);
  gtk_window_set_child(window, canvas);
  gtk_window_present(window);

  cairo_region_t *empty = cairo_region_create();
  gdk_surface_set_input_region(gtk_native_get_surface(GTK_NATIVE(window)), empty);
  cairo_region_destroy(empty);
  g_timeout_add(100, ready, NULL);

  GMainLoop *loop = g_main_loop_new(NULL, FALSE);
  g_main_loop_run(loop);
  return 0;
}
