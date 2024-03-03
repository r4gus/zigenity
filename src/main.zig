const std = @import("std");
const gtk = @import("gtk.zig");

pub fn ok_callback(_: *gtk.GtkWidget, _: gtk.gpointer) void {
    gtk.g_print("You clicked Ok\n");
}

pub fn cancel_callback(_: *gtk.GtkWidget, _: gtk.gpointer) void {
    gtk.g_print("You clicked Cancel\n");
}

/// Center the given window on the screen
fn centerWindow(window: *gtk.GtkWidget) void {
    var screen_rect: gtk.GdkRectangle = undefined;
    var window_width: gtk.gint = 0;
    var window_height: gtk.gint = 0;
    var x: gtk.gint = 0;
    var y: gtk.gint = 0;

    const screen = gtk.gdk_screen_get_default();
    gtk.gdk_screen_get_monitor_geometry(screen, gtk.gdk_screen_get_primary_monitor(screen), &screen_rect);
    gtk.gtk_window_get_size(@as(*gtk.GtkWindow, @ptrCast(window)), &window_width, &window_height);

    x = @divTrunc(screen_rect.width - window_width, 2);
    y = @divTrunc(screen_rect.height - window_height, 2);

    gtk.gtk_window_move(@as(*gtk.GtkWindow, @ptrCast(window)), x, y);
}

fn question(app: *gtk.GtkApplication, _: gtk.gpointer) void {
    const window_widget: *gtk.GtkWidget = gtk.gtk_application_window_new(app);
    const window = @as(*gtk.GtkWindow, @ptrCast(window_widget));
    gtk.gtk_window_set_title(window, "Question");
    gtk.gtk_window_set_default_size(window, 360, 180);
    gtk.gtk_container_set_border_width(@as(*gtk.GtkContainer, @ptrCast(window_widget)), 10);

    const vbox: *gtk.GtkWidget = gtk.gtk_box_new(gtk.GTK_ORIENTATION_VERTICAL, 5);
    gtk.gtk_container_add(@as(*gtk.GtkContainer, @ptrCast(window)), vbox);

    const label = gtk.gtk_label_new("Are you sure you want to proceed?");
    gtk.gtk_box_pack_start(@as(*gtk.GtkBox, @ptrCast(vbox)), label, 1, 1, 0);

    const hbox: *gtk.GtkWidget = gtk.gtk_box_new(gtk.GTK_ORIENTATION_HORIZONTAL, 5);
    gtk.gtk_box_pack_end(@as(*gtk.GtkBox, @ptrCast(vbox)), hbox, 0, 0, 0);

    const cancel_button: *gtk.GtkWidget = gtk.gtk_button_new_with_label("Cancel");
    _ = gtk.g_signal_connect_(cancel_button, "clicked", @as(gtk.GCallback, @ptrCast(&cancel_callback)), null);
    gtk.gtk_box_pack_start(@as(*gtk.GtkBox, @ptrCast(hbox)), cancel_button, 1, 1, 0);

    const ok_button: *gtk.GtkWidget = gtk.gtk_button_new_with_label("Ok");
    _ = gtk.g_signal_connect_(ok_button, "clicked", @as(gtk.GCallback, @ptrCast(&ok_callback)), null);
    gtk.gtk_box_pack_start(@as(*gtk.GtkBox, @ptrCast(hbox)), ok_button, 1, 1, 0);

    centerWindow(window_widget);
    gtk.gtk_widget_show_all(window_widget);
}

pub fn main() !u8 {
    var app = gtk.gtk_application_new("de.sugaryourcoffee.zigenity", gtk.G_APPLICATION_FLAGS_NONE);
    defer gtk.g_object_unref(app);

    _ = gtk.g_signal_connect_(app, "activate", @as(gtk.GCallback, @ptrCast(&question)), null);
    const status: i32 = gtk.g_application_run(@as(*gtk.GApplication, @ptrCast(app)), 0, null);

    return @as(u8, @intCast(status));
}
