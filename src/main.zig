const std = @import("std");
const gtk = @import("gtk.zig");

var application: *gtk.GtkApplication = undefined;

var return_code: u8 = 0;
var typ: DialogType = .None;
var title: [:0]const u8 = "Title";
var title_changed = false;
var width: gtk.gint = 360;
var height: gtk.gint = 180;
var ok_label: [:0]const u8 = "Yes";
var cancel_label: [:0]const u8 = "No";

const DialogType = enum {
    Question,
    Help,
    HelpGeneral,
    None,

    pub fn fromString(s: []const u8) DialogType {
        if (std.mem.eql(u8, "-h", s) or std.mem.eql(u8, "--help", s)) {
            return .Help;
        } else if (std.mem.eql(u8, "--help-general", s)) {
            return .HelpGeneral;
        } else if (std.mem.eql(u8, "--question", s)) {
            if (!title_changed) title = "Question";
            return .Question;
        } else {
            return .None;
        }
    }
};

const help_text =
    \\Usage:
    \\  zigenity [OPTION...]
    \\
    \\Help Options:
    \\  -h, --help                        Show help options
    \\  --help-general                    Show general options
    \\
    \\Application Options:
    \\  --question                        Display a question dialog
;

const help_general =
    \\Usage:
    \\  zigenity [OPTION...]
    \\
    \\General options:
    \\  --title=TITLE                     Set the dialog title
    \\  --width=WIDTH                     Set the window width
    \\  --height=HEIGHT                   Set the window height
    \\  --ok-label=TEXT                   Set the label of the OK button
    \\  --cancel-label=TEXT               Set the label of the Cancel button
;

pub fn ok_callback(_: *gtk.GtkWidget, _: gtk.gpointer) void {
    //gtk.g_print("You clicked Ok\n");
    gtk.g_application_quit(@as(*gtk.GApplication, @ptrCast(application)));
}

pub fn cancel_callback(_: *gtk.GtkWidget, _: gtk.gpointer) void {
    //gtk.g_print("You clicked Cancel\n");
    return_code = 1;
    gtk.g_application_quit(@as(*gtk.GApplication, @ptrCast(application)));
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
    gtk.gtk_window_set_title(window, title);
    gtk.gtk_window_set_default_size(window, width, height);
    gtk.gtk_container_set_border_width(@as(*gtk.GtkContainer, @ptrCast(window_widget)), 10);

    const vbox: *gtk.GtkWidget = gtk.gtk_box_new(gtk.GTK_ORIENTATION_VERTICAL, 5);
    gtk.gtk_container_add(@as(*gtk.GtkContainer, @ptrCast(window)), vbox);

    const label = gtk.gtk_label_new("Are you sure you want to proceed?");
    gtk.gtk_box_pack_start(@as(*gtk.GtkBox, @ptrCast(vbox)), label, 1, 1, 0);

    const hbox: *gtk.GtkWidget = gtk.gtk_box_new(gtk.GTK_ORIENTATION_HORIZONTAL, 5);
    gtk.gtk_box_pack_end(@as(*gtk.GtkBox, @ptrCast(vbox)), hbox, 0, 0, 0);

    const cancel_button: *gtk.GtkWidget = gtk.gtk_button_new_with_label(cancel_label);
    _ = gtk.g_signal_connect_(cancel_button, "clicked", @as(gtk.GCallback, @ptrCast(&cancel_callback)), null);
    gtk.gtk_box_pack_start(@as(*gtk.GtkBox, @ptrCast(hbox)), cancel_button, 1, 1, 0);

    const ok_button: *gtk.GtkWidget = gtk.gtk_button_new_with_label(ok_label);
    _ = gtk.g_signal_connect_(ok_button, "clicked", @as(gtk.GCallback, @ptrCast(&ok_callback)), null);
    gtk.gtk_box_pack_start(@as(*gtk.GtkBox, @ptrCast(hbox)), ok_button, 1, 1, 0);

    centerWindow(window_widget);
    gtk.gtk_widget_show_all(window_widget);
}

/// Parse option. Errors are silently discarded.
fn parseOptions() void {
    for (std.os.argv[1..]) |arg| {
        // Note that arg is a NULL terminated string
        var s = arg[0..strlen(arg)];
        // Here we check if the argument is related to the type of dialog
        // and if yes, set it. This also includes the --help flag.
        const t = DialogType.fromString(s);
        if (t != .None) {
            typ = t;
            continue;
        }

        s = arg[0 .. strlen(arg) + 1]; // here we include the 0
        var iter = std.mem.split(u8, s, "=");
        const option_ = iter.next();
        const argument_ = iter.next();
        const please_dont = iter.next();
        // Here we make sure the 'argument' is the second half of 'arg' because
        // this implies that it is null-terminated, i.e., we can safely cast
        // argument from a '[]const u8' to a '[:0]const u8'.
        if (option_ == null or argument_ == null or please_dont != null) continue;
        const option = option_.?;
        const argument: [:0]const u8 = @ptrCast(argument_.?);
        const argument_no_null = argument[0 .. argument.len - 1];

        if (std.mem.eql(u8, "--title", option)) {
            title = argument;
        } else if (std.mem.eql(u8, "--width", option)) {
            width = std.fmt.parseInt(gtk.gint, argument_no_null, 0) catch {
                continue;
            };
        } else if (std.mem.eql(u8, "--height", option)) {
            height = std.fmt.parseInt(gtk.gint, argument_no_null, 0) catch {
                continue;
            };
        } else if (std.mem.eql(u8, "--ok-label", option)) {
            ok_label = argument;
        } else if (std.mem.eql(u8, "--cancel-label", option)) {
            cancel_label = argument;
        }
    }
}

pub fn main() !u8 {
    parseOptions();

    application = gtk.gtk_application_new("de.sugaryourcoffee.zigenity", gtk.G_APPLICATION_FLAGS_NONE);
    defer gtk.g_object_unref(application);

    switch (typ) {
        .Question => _ = gtk.g_signal_connect_(application, "activate", @as(gtk.GCallback, @ptrCast(&question)), null),
        .Help => {
            try std.io.getStdOut().writeAll(help_text);
            return 0;
        },
        .HelpGeneral => {
            try std.io.getStdOut().writeAll(help_general);
            return 0;
        },
        else => {
            try std.io.getStdErr().writeAll("You must specify a dialog type. See 'zigenity --help' for details\n");
            return 255;
        },
    }
    const status: i32 = gtk.g_application_run(@as(*gtk.GApplication, @ptrCast(application)), 0, null);
    _ = status;

    return return_code;
}

pub fn strlen(s: [*c]const u8) usize {
    var i: usize = 0;
    while (s[i] != 0) : (i += 1) {}
    return i;
}
