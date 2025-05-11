const std = @import("std");
const builtin = @import("builtin");
const dvui = @import("dvui");
const Backend = dvui.backend;
comptime {
    std.debug.assert(@hasDecl(Backend, "SDLBackend"));
}

var gpa_instance = std.heap.GeneralPurposeAllocator(.{}){};
const gpa = gpa_instance.allocator();

const vsync = true;
var scale_val: f32 = 1.0;

var g_backend: ?Backend = null;

var typ: DialogType = .None;
var directory_only: bool = false;
var switch_ok: bool = false;
var switch_cancel: bool = false;
var title: ?[:0]const u8 = null;
var window_icon: ?[]const u8 = null;
var width: f32 = 450.0;
var height: f32 = 160.0;
var ok_label: ?[]const u8 = null;
var cancel_label: ?[]const u8 = null;
var text: ?[]const u8 = null;
var timeout: ?i32 = null;
var base_icon: ?[]const u8 = null;

var return_code: u8 = 0;
var quit_loop: bool = false;
var pw_buffer: [256]u8 = .{0} ** 256;

pub fn main() !u8 {
    std.log.info("SDL version: {}", .{Backend.getSDLVersion()});

    defer if (gpa_instance.deinit() != .ok) @panic("Memory leak on exit!");
    defer {
        if (title) |v| gpa.free(v);
        if (ok_label) |v| gpa.free(v);
        if (cancel_label) |v| gpa.free(v);
        if (text) |v| gpa.free(v);
        if (base_icon) |v| gpa.free(v);
        if (window_icon) |v| gpa.free(v);
    }

    try parseOptions();

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
        else => {},
    }

    // init SDL backend (creates and owns OS window)
    var backend = try Backend.initWindow(.{
        .allocator = gpa,
        .size = .{ .w = width, .h = height },
        .min_size = .{ .w = 100.0, .h = 100.0 },
        .vsync = vsync,
        .title = if (title) |t| t else "zigenity",
        //.icon = window_icon_png, // can also call setIconFromFileContent()
        .icon = if (window_icon) |icon| icon else null,
    });
    g_backend = backend;
    defer backend.deinit();

    // init dvui Window (maps onto a single OS window)
    var win = try dvui.Window.init(@src(), gpa, backend.backend(), .{});
    defer win.deinit();

    main_loop: while (!quit_loop) {
        // beginWait coordinates with waitTime below to run frames only when needed
        const nstime = win.beginWait(backend.hasEvent());

        // marks the beginning of a frame for dvui, can call dvui functions after this
        try win.begin(nstime);

        // send all SDL events to dvui for processing
        const quit = try backend.addAllEvents(&win);
        if (quit) break :main_loop;

        if (timeout) |tout| {
            if (dvui.timerDoneOrNone(win.wd.id)) {
                if (dvui.timerDone(win.wd.id)) {
                    return_code = 5;
                    break :main_loop;
                }
                try dvui.timer(win.wd.id, tout);
            }
        }

        // if dvui widgets might not cover the whole window, then need to clear
        // the previous frame's render
        _ = Backend.c.SDL_SetRenderDrawColor(backend.renderer, 255, 255, 255, 255);
        _ = Backend.c.SDL_RenderClear(backend.renderer);

        // The demos we pass in here show up under "Platform-specific demos"
        switch (typ) {
            .Question => try questionFrame(),
            .Password => try passwordFrame(),
            else => {},
        }

        // marks end of dvui frame, don't call dvui functions after this
        // - sends all dvui stuff to backend for rendering, must be called before renderPresent()
        const end_micros = try win.end(.{});

        // cursor management
        backend.setCursor(win.cursorRequested());
        backend.textInputRect(win.textInputRequested());

        // render frame to OS
        backend.renderPresent();

        // waitTime and beginWait combine to achieve variable framerates
        const wait_event_micros = win.waitTime(end_micros, null);
        backend.waitEventTimeout(wait_event_micros);
    }

    return return_code;
}

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
    \\
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
    \\
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
    \\
;

const help_password =
    \\Usage:
    \\  zigenity [OPTION...]
    \\
    \\Password options:
    \\  --password                        Display a password dialog
    \\  --text=TEXT                       Set the dialog text
    \\
;

const help_file_selection =
    \\Usage:
    \\  zigenity [OPTION...]
    \\
    \\File Selection options:
    \\  --file-selection                  Display file selection dialog
    \\  --directory                       Activate directory-only selection
    \\
;

/// Parse option. Errors are silently discarded.
fn parseOptions() !void {
    var iter = try std.process.argsWithAllocator(gpa);
    defer iter.deinit();

    _ = iter.skip();

    while (iter.next()) |arg| {
        // Note that arg is a NULL terminated string
        const s: []const u8 = arg;
        // Here we check if the argument is related to the type of dialog
        // and if yes, set it. This also includes the --help flag.
        const t = DialogType.fromString(s);
        if (t != .None) {
            typ = t;
            continue;
        }

        var iter2 = std.mem.splitSequence(u8, s, "=");
        const option_ = iter2.next();
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

        const argument_ = iter2.next();
        const please_dont = iter2.next();
        if (argument_ == null or please_dont != null) continue;
        const argument: []const u8 = @ptrCast(argument_.?);

        if (std.mem.eql(u8, "--title", option)) {
            title = try gpa.dupeZ(u8, argument);
        } else if (std.mem.eql(u8, "--window-icon", option)) {
            const f = std.fs.openFileAbsolute(argument, .{}) catch |e| {
                std.log.err("unable to open icon file '{s}' ({any})", .{ argument, e });
                continue;
            };
            defer f.close();

            window_icon = f.readToEndAlloc(gpa, 50_000_000) catch |e| {
                std.log.err("unable to read icon file '{s}' ({any})", .{ argument, e });
                continue;
            };
        } else if (std.mem.eql(u8, "--width", option)) {
            width = std.fmt.parseFloat(f32, argument) catch {
                continue;
            };
        } else if (std.mem.eql(u8, "--height", option)) {
            height = std.fmt.parseFloat(f32, argument) catch {
                continue;
            };
        } else if (std.mem.eql(u8, "--ok-label", option)) {
            ok_label = try gpa.dupe(u8, argument);
        } else if (std.mem.eql(u8, "--cancel-label", option)) {
            cancel_label = try gpa.dupe(u8, argument);
        } else if (std.mem.eql(u8, "--text", option)) {
            text = try gpa.dupe(u8, argument);
        } else if (std.mem.eql(u8, "--timeout", option)) {
            const timeout_ = std.fmt.parseInt(i32, argument, 0) catch {
                continue;
            };

            // Time must be between 1 second and one hour
            if (timeout_ > 0 and timeout_ < 3600) {
                timeout = timeout_ * 1000000; // the timeout is specified in us
            }
        } else if (std.mem.eql(u8, "--icon", option)) {
            const f = std.fs.openFileAbsolute(argument, .{}) catch |e| {
                std.log.err("unable to open icon file '{s}' ({any})", .{ argument, e });
                continue;
            };
            defer f.close();

            base_icon = f.readToEndAlloc(gpa, 50_000_000) catch |e| {
                std.log.err("unable to read icon file '{s}' ({any})", .{ argument, e });
                continue;
            };
        }
    }
}

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
            return .Question;
        } else if (std.mem.eql(u8, "--password", s)) {
            return .Password;
        } else if (std.mem.eql(u8, "--file-selection", s)) {
            return .FileSelection;
        } else {
            return .None;
        }
    }
};

pub fn strlen(s: [*c]const u8) usize {
    var i: usize = 0;
    while (s[i] != 0) : (i += 1) {}
    return i;
}

fn questionFrame() !void {
    const vbox = try dvui.box(@src(), .vertical, .{ .expand = .both });
    defer vbox.deinit();

    var tl = dvui.TextLayoutWidget.init(
        @src(),
        .{},
        .{
            .margin = .all(12.0),
            .gravity_x = 0.5,
            .gravity_y = 0.5,
        },
    );
    try tl.install(.{});

    try tl.addText(
        if (text) |t| t else "Are you sure you want to proceed?",
        .{
            .gravity_x = 0.5,
            .expand = .horizontal,
        },
    );

    tl.deinit();

    const hbox = try dvui.box(@src(), .horizontal, .{ .expand = .horizontal, .gravity_y = 1.0 });
    {
        if (try dvui.button(@src(), if (cancel_label) |label| label else "No", .{}, .{ .expand = .horizontal })) {
            return_code = 1;
            quit_loop = true;
        }

        if (try dvui.button(@src(), if (ok_label) |label| label else "Yes", .{}, .{ .expand = .horizontal })) {
            return_code = 0;
            quit_loop = true;
        }
    }
    hbox.deinit();
}

fn passwordFrame() !void {
    const vbox = try dvui.box(@src(), .vertical, .{ .expand = .both });
    defer vbox.deinit();

    var tl = dvui.TextLayoutWidget.init(
        @src(),
        .{},
        .{
            .margin = .all(12.0),
            .gravity_x = 0.5,
            .gravity_y = 0.5,
        },
    );
    try tl.install(.{});

    try tl.addText(
        if (text) |t| t else "Type your password",
        .{
            .gravity_x = 0.5,
            .expand = .horizontal,
        },
    );

    tl.deinit();

    var te = try dvui.textEntry(@src(), .{
        .text = .{ .buffer = &pw_buffer },
        .password_char = "*",
    }, .{ .expand = .horizontal });

    if (dvui.firstFrame(te.data().id)) {
        dvui.focusWidget(te.data().id, null, null);
    }

    const l = te.len;

    const enter_pressed = te.enter_pressed;

    te.deinit();

    const hbox = try dvui.box(@src(), .horizontal, .{ .expand = .horizontal, .gravity_y = 1.0 });

    if (try dvui.button(@src(), if (cancel_label) |label| label else "Cancel", .{}, .{ .expand = .horizontal })) {
        std.crypto.secureZero(u8, pw_buffer[0..]);
        return_code = 1;
        quit_loop = true;
    }

    if (try dvui.button(@src(), if (ok_label) |label| label else "OK", .{}, .{ .expand = .horizontal }) or enter_pressed) {
        try std.io.getStdOut().writer().print("{s}\n", .{pw_buffer[0..l]});
        std.crypto.secureZero(u8, pw_buffer[0..]);
        return_code = 0;
        quit_loop = true;
    }

    hbox.deinit();
}
