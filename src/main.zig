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
var switch_ok: bool = false;
var cancel_label: [:0]const u8 = "No";
var switch_cancel: bool = false;
var timeout: ?gtk.guint = null;
var window_icon: ?[:0]const u8 = null;
var base_icon: ?[:0]const u8 = null;

var text: [:0]const u8 = "";
var text_changed = false;

var directory_only: bool = false;

const DialogType = enum {
    Question,
    Password,
    FileSelection,
    Help,
    HelpGeneral,
    HelpQuestion,
    HelpPassword,
    HelpFileSelection,
    None,

    pub fn fromString(s: []const u8) DialogType {
        if (std.mem.eql(u8, "-h", s) or std.mem.eql(u8, "--help", s)) {
            return .Help;
        } else if (std.mem.eql(u8, "--help-general", s)) {
            return .HelpGeneral;
        } else if (std.mem.eql(u8, "--help-question", s)) {
            return .HelpQuestion;
        } else if (std.mem.eql(u8, "--help-password", s)) {
            return .HelpPassword;
        } else if (std.mem.eql(u8, "--help-file-selection", s)) {
            return .HelpFileSelection;
        } else if (std.mem.eql(u8, "--question", s)) {
            if (!title_changed) title = "Question";
            if (!text_changed) text = "Are you sure you want to proceed?";
            return .Question;
        } else if (std.mem.eql(u8, "--password", s)) {
            if (!title_changed) title = "Password";
            if (!text_changed) text = "Type your password";
            return .Password;
        } else if (std.mem.eql(u8, "--file-selection", s)) {
            return .FileSelection;
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
    \\  --help-question                   Show question options
    \\
    \\Application Options:
    \\  --question                        Display a question dialog
    \\  --password                        Display a password dialog
;

const help_general =
    \\Usage:
    \\  zigenity [OPTION...]
    \\
    \\General options:
    \\  --title=TITLE                     Set the dialog title
    \\  --window-icon=ICONPATH            Set the window icon
    \\  --width=WIDTH                     Set the window width
    \\  --height=HEIGHT                   Set the window height
    \\  --timeout=TIMEOUT                 Set dialog timeout in seconds
    \\  --ok-label=TEXT                   Set the label of the OK button
    \\  --cancel-label=TEXT               Set the label of the Cancel button
;

const help_question =
    \\Usage:
    \\  zigenity [OPTION...]
    \\
    \\Question options:
    \\  --question                        Display a question dialog
    \\  --text=TEXT                       Set the dialog text
    \\  --icon=ICONPATH                   Set the icon
    \\  --switch-ok                       Suppress OK button
    \\  --switch-cancel                   Suppress Cancel button
;

const help_password =
    \\Usage:
    \\  zigenity [OPTION...]
    \\
    \\Password options:
    \\  --password                        Display a password dialog
    \\  --text=TEXT                       Set the dialog text
;

const help_file_selection =
    \\Usage:
    \\  zigenity [OPTION...]
    \\
    \\File Selection options:
    \\  --file-selection                  Display file selection dialog
    \\  --directory                       Activate directory-only selection
;

pub fn ok_callback(_: *gtk.GtkWidget, data: gtk.gpointer) void {
    if (typ == .Password) {
        const entry = @as(*gtk.GtkEntry, @ptrCast(@alignCast(data.?)));
        const password = gtk.gtk_entry_get_text(entry);
        std.io.getStdOut().writer().print("{s}\n", .{password[0..strlen(password)]}) catch {
            return_code = 254; // TODO: what would indicate such a failure?
        };
    }

    gtk.g_application_quit(@as(*gtk.GApplication, @ptrCast(application)));
}

const GdkEventKey = extern struct {
    typ: gtk.GdkEventType,
    window: *gtk.GdkWindow,
    send_event: gtk.gint8,
    time: gtk.guint32,
    state: gtk.guint,
    keyval: gtk.guint,
    length: gtk.gint,
    string: [*c]gtk.gchar,
    hardware_keycode: gtk.guint16,
    group: gtk.guint8,
    // TODO bit field guint is_modifier : 1;
};

pub fn on_key_press(w: *gtk.GtkWidget, event: *GdkEventKey, data: gtk.gpointer) gtk.gboolean {
    if (event.keyval == gtk.GDK_KEY_Return) {
        ok_callback(w, data);
    }

    return 0;
}

pub fn cancel_callback(_: *gtk.GtkWidget, _: gtk.gpointer) void {
    //gtk.g_print("You clicked Cancel\n");
    return_code = 1;
    gtk.g_application_quit(@as(*gtk.GApplication, @ptrCast(application)));
}

pub fn timer_callback(data: gtk.gpointer) callconv(.C) gtk.gboolean {
    _ = data;
    return_code = 5;
    gtk.g_application_quit(@as(*gtk.GApplication, @ptrCast(application)));
    return gtk.G_SOURCE_REMOVE;
}

pub fn file_callback(chooser: *gtk.GtkFileChooser, _: gtk.gpointer) void {
    const fname = gtk.gtk_file_chooser_get_filename(chooser);
    std.io.getStdOut().writer().print("{s}\n", .{fname[0..strlen(fname)]}) catch {
        return_code = 254; // TODO: what would indicate such a failure?
    };

    gtk.g_application_quit(@as(*gtk.GApplication, @ptrCast(application)));
}

pub fn file_button_callback(dialog: *gtk.GtkDialog, response_id: gtk.gint, _: gtk.gpointer) void {
    if (response_id == gtk.GTK_RESPONSE_ACCEPT) {
        const chooser = @as(*gtk.GtkFileChooser, @ptrCast(dialog));
        const fname = gtk.gtk_file_chooser_get_filename(chooser);
        std.io.getStdOut().writer().print("{s}\n", .{fname[0..strlen(fname)]}) catch {
            return_code = 254; // TODO: what would indicate such a failure?
        };
    } else { // Cancel
        return_code = 1;
    }

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

fn activate(app: *gtk.GtkApplication, _: gtk.gpointer) void {
    var window_widget: *gtk.GtkWidget = gtk.gtk_application_window_new(app);
    const window = @as(*gtk.GtkWindow, @ptrCast(window_widget));
    gtk.gtk_window_set_title(window, title);
    _ = gtk.g_signal_connect_(window, "delete-event", @as(gtk.GCallback, @ptrCast(&cancel_callback)), null);
    gtk.gtk_window_set_default_size(window, width, height);
    gtk.gtk_container_set_border_width(@as(*gtk.GtkContainer, @ptrCast(window_widget)), 10);

    if (window_icon) |icon_path| {
        var err: [*c]gtk.GError = 0;
        const icon = gtk.gdk_pixbuf_new_from_file(icon_path, &err);

        if (err == 0) {
            gtk.gtk_window_set_icon(window, icon);
        }
    }

    centerWindow(window_widget);

    switch (typ) {
        .Question => questionDialog(window_widget),
        .Password => passwordDialog(window_widget),
        .FileSelection => window_widget = fileDialog(window_widget),
        else => unreachable,
    }

    gtk.gtk_widget_show_all(window_widget);
}

fn questionDialog(window_widget: *gtk.GtkWidget) void {
    const vbox: *gtk.GtkWidget = gtk.gtk_box_new(gtk.GTK_ORIENTATION_VERTICAL, 5);
    gtk.gtk_container_add(@as(*gtk.GtkContainer, @ptrCast(window_widget)), vbox);

    const tbox: *gtk.GtkWidget = gtk.gtk_box_new(gtk.GTK_ORIENTATION_HORIZONTAL, 5);
    gtk.gtk_box_pack_start(@as(*gtk.GtkBox, @ptrCast(vbox)), tbox, 1, 1, 0);

    if (base_icon) |icon_path| {
        var err: [*c]gtk.GError = 0;
        const icon = gtk.gdk_pixbuf_new_from_file_at_scale(icon_path, 64, 64, 1, &err);

        if (err == 0) {
            const image = gtk.gtk_image_new_from_pixbuf(icon);
            gtk.gtk_box_pack_start(@as(*gtk.GtkBox, @ptrCast(tbox)), image, 1, 1, 0);
        }
    }

    const label = gtk.gtk_label_new(text);
    gtk.gtk_box_pack_start(@as(*gtk.GtkBox, @ptrCast(tbox)), label, 1, 1, 0);

    const hbox: *gtk.GtkWidget = gtk.gtk_box_new(gtk.GTK_ORIENTATION_HORIZONTAL, 5);
    gtk.gtk_box_pack_end(@as(*gtk.GtkBox, @ptrCast(vbox)), hbox, 0, 0, 0);

    if (!switch_cancel) {
        const cancel_button: *gtk.GtkWidget = gtk.gtk_button_new_with_label(cancel_label);
        _ = gtk.g_signal_connect_(cancel_button, "clicked", @as(gtk.GCallback, @ptrCast(&cancel_callback)), null);
        gtk.gtk_box_pack_start(@as(*gtk.GtkBox, @ptrCast(hbox)), cancel_button, 1, 1, 0);
    }

    if (!switch_ok) {
        const ok_button: *gtk.GtkWidget = gtk.gtk_button_new_with_label(ok_label);
        _ = gtk.g_signal_connect_(ok_button, "clicked", @as(gtk.GCallback, @ptrCast(&ok_callback)), null);
        gtk.gtk_box_pack_start(@as(*gtk.GtkBox, @ptrCast(hbox)), ok_button, 1, 1, 0);
    }
}

fn passwordDialog(window_widget: *gtk.GtkWidget) void {
    const vbox: *gtk.GtkWidget = gtk.gtk_box_new(gtk.GTK_ORIENTATION_VERTICAL, 5);
    gtk.gtk_container_add(@as(*gtk.GtkContainer, @ptrCast(window_widget)), vbox);

    const label = gtk.gtk_label_new(text);
    gtk.gtk_box_pack_start(@as(*gtk.GtkBox, @ptrCast(vbox)), label, 1, 1, 0);

    const entry = gtk.gtk_entry_new();
    gtk.gtk_entry_set_visibility(@as(*gtk.GtkEntry, @ptrCast(entry)), 0);
    gtk.gtk_entry_set_invisible_char(@as(*gtk.GtkEntry, @ptrCast(entry)), '*');
    gtk.gtk_entry_set_placeholder_text(@as(*gtk.GtkEntry, @ptrCast(entry)), "Enter password");
    gtk.gtk_box_pack_start(@as(*gtk.GtkBox, @ptrCast(vbox)), entry, 0, 0, 0);

    const hbox: *gtk.GtkWidget = gtk.gtk_box_new(gtk.GTK_ORIENTATION_HORIZONTAL, 5);
    gtk.gtk_box_pack_end(@as(*gtk.GtkBox, @ptrCast(vbox)), hbox, 0, 0, 0);

    const cancel_button: *gtk.GtkWidget = gtk.gtk_button_new_with_label(cancel_label);
    _ = gtk.g_signal_connect_(cancel_button, "clicked", @as(gtk.GCallback, @ptrCast(&cancel_callback)), null);
    gtk.gtk_box_pack_start(@as(*gtk.GtkBox, @ptrCast(hbox)), cancel_button, 1, 1, 0);

    const ok_button: *gtk.GtkWidget = gtk.gtk_button_new_with_label(ok_label);
    _ = gtk.g_signal_connect_(ok_button, "clicked", @as(gtk.GCallback, @ptrCast(&ok_callback)), entry);
    gtk.gtk_box_pack_start(@as(*gtk.GtkBox, @ptrCast(hbox)), ok_button, 1, 1, 0);

    _ = gtk.g_signal_connect_(window_widget, "key-press-event", @as(gtk.GCallback, @ptrCast(&on_key_press)), entry);
}

fn fileDialog(window_widget: *gtk.GtkWidget) *gtk.GtkWidget {
    const action: c_uint = if (directory_only) blk: {
        break :blk gtk.GTK_FILE_CHOOSER_ACTION_SELECT_FOLDER;
    } else blk: {
        break :blk gtk.GTK_FILE_CHOOSER_ACTION_OPEN;
    };

    const file_chooser = gtk.gtk_file_chooser_dialog_new(
        "Open File",
        @as(*gtk.GtkWindow, @ptrCast(window_widget)),
        action,
        "Cancel",
        gtk.GTK_RESPONSE_CANCEL,
        "Open",
        gtk.GTK_RESPONSE_ACCEPT,
        @as(usize, @intCast(0)),
    );

    _ = gtk.g_signal_connect_(file_chooser, "file-activated", @as(gtk.GCallback, @ptrCast(&file_callback)), null);
    _ = gtk.g_signal_connect_(file_chooser, "response", @as(gtk.GCallback, @ptrCast(&file_button_callback)), null);

    return file_chooser;
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
        // Here we make sure the 'argument' is the second half of 'arg' because
        // this implies that it is null-terminated, i.e., we can safely cast
        // argument from a '[]const u8' to a '[:0]const u8'.
        if (option_ == null) continue;
        const option = option_.?;

        if (std.mem.startsWith(u8, option, "--directory")) {
            directory_only = true;
        } else if (std.mem.startsWith(u8, option, "--switch-ok")) {
            switch_ok = true;
        } else if (std.mem.startsWith(u8, option, "--switch-cancel")) {
            switch_cancel = true;
        }

        const argument_ = iter.next();
        const please_dont = iter.next();
        if (argument_ == null or please_dont != null) continue;
        const argument: [:0]const u8 = @ptrCast(argument_.?);
        const argument_no_null = argument[0 .. argument.len - 1];

        if (std.mem.eql(u8, "--title", option)) {
            title = argument;
            title_changed = true;
        } else if (std.mem.eql(u8, "--window-icon", option)) {
            window_icon = argument;
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
        } else if (std.mem.eql(u8, "--text", option)) {
            text = argument;
            text_changed = true;
        } else if (std.mem.eql(u8, "--timeout", option)) {
            const timeout_ = std.fmt.parseInt(gtk.guint, argument_no_null, 0) catch {
                continue;
            };

            // Time must be between 1 second and one hour
            if (timeout_ > 0 and timeout_ < 3600) {
                timeout = timeout_ * 1000; // the timeout is specified in ms
            }
        } else if (std.mem.eql(u8, "--icon", option)) {
            base_icon = argument;
        }
    }
}

pub fn main() !u8 {
    parseOptions();

    application = gtk.gtk_application_new("de.sugaryourcoffee.zigenity", gtk.G_APPLICATION_FLAGS_NONE);
    defer gtk.g_object_unref(application);

    switch (typ) {
        .Help => {
            try std.io.getStdOut().writeAll(help_text);
            return 0;
        },
        .HelpGeneral => {
            try std.io.getStdOut().writeAll(help_general);
            return 0;
        },
        .HelpQuestion => {
            try std.io.getStdOut().writeAll(help_question);
            return 0;
        },
        .HelpPassword => {
            try std.io.getStdOut().writeAll(help_password);
            return 0;
        },
        .HelpFileSelection => {
            try std.io.getStdOut().writeAll(help_file_selection);
            return 0;
        },
        .None => {
            try std.io.getStdErr().writeAll("You must specify a dialog type. See 'zigenity --help' for details\n");
            return 255;
        },
        else => _ = gtk.g_signal_connect_(application, "activate", @as(gtk.GCallback, @ptrCast(&activate)), null),
    }

    if (timeout) |tout| {
        _ = gtk.g_timeout_add(tout, timer_callback, null);
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
