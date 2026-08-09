/// uinput-backed virtual input devices.
///
/// Creates one virtual mouse and one virtual keyboard using /dev/uinput.
/// Requires /dev/uinput to be accessible (see README.md for permissions).

use anyhow::Result;
use uinput::event::keyboard::Key;
use uinput::event::relative::{Position, Wheel};
use uinput::event::controller::{Controller, Mouse};
use uinput::Device;

pub struct VirtualMouse {
    device: Device,
}

pub struct VirtualKeyboard {
    device: Device,
}

impl VirtualMouse {
    pub fn new() -> Result<Self> {
        let device = uinput::default()?
            .name("DevControl Virtual Mouse")?
            // Relative axes for movement
            .event(Position::X)?
            .event(Position::Y)?
            // Scroll wheels
            .event(Wheel::Vertical)?
            .event(Wheel::Horizontal)?
            // Mouse buttons — must register as Controller::Mouse to satisfy Press/Release traits
            .event(Controller::Mouse(Mouse::Left))?
            .event(Controller::Mouse(Mouse::Right))?
            .event(Controller::Mouse(Mouse::Middle))?
            .create()?;

        Ok(Self { device })
    }

    /// Relative mouse movement.
    pub fn move_rel(&mut self, dx: i16, dy: i16) -> Result<()> {
        if dx != 0 {
            self.device.position(&Position::X, dx as i32)?;
        }
        if dy != 0 {
            self.device.position(&Position::Y, dy as i32)?;
        }
        self.device.synchronize()?;
        Ok(())
    }

    /// Press or release a mouse button (0=left, 1=right, 2=middle).
    pub fn button(&mut self, btn: u8, pressed: bool) -> Result<()> {
        let event = match btn {
            0 => Controller::Mouse(Mouse::Left),
            1 => Controller::Mouse(Mouse::Right),
            2 => Controller::Mouse(Mouse::Middle),
            _ => return Ok(()),
        };
        if pressed {
            self.device.press(&event)?;
        } else {
            self.device.release(&event)?;
        }
        self.device.synchronize()?;
        Ok(())
    }

    /// Scroll: dy = vertical (positive = scroll up), dx = horizontal.
    pub fn scroll(&mut self, dx: i16, dy: i16) -> Result<()> {
        if dy != 0 {
            self.device.position(&Wheel::Vertical, dy as i32)?;
        }
        if dx != 0 {
            self.device.position(&Wheel::Horizontal, dx as i32)?;
        }
        self.device.synchronize()?;
        Ok(())
    }
}

impl VirtualKeyboard {
    pub fn new() -> Result<Self> {
        let mut builder = uinput::default()?.name("DevControl Virtual Keyboard")?;

        for key in all_supported_keys() {
            builder = builder.event(key)?;
        }

        let device = builder.create()?;
        Ok(Self { device })
    }

    /// Press a key (key down).
    pub fn key_down(&mut self, keycode: u16) -> Result<()> {
        if let Some(key) = linux_keycode_to_key(keycode) {
            self.device.press(&key)?;
            self.device.synchronize()?;
        }
        Ok(())
    }

    /// Release a key (key up).
    pub fn key_up(&mut self, keycode: u16) -> Result<()> {
        if let Some(key) = linux_keycode_to_key(keycode) {
            self.device.release(&key)?;
            self.device.synchronize()?;
        }
        Ok(())
    }
}

/// Map Linux evdev keycodes (from linux/input-event-codes.h) to uinput Key enum.
/// These match the keycode values sent by Flutter's physical key → Linux evdev mapping.
fn linux_keycode_to_key(code: u16) -> Option<Key> {
    match code {
        1   => Some(Key::Esc),
        2   => Some(Key::_1),
        3   => Some(Key::_2),
        4   => Some(Key::_3),
        5   => Some(Key::_4),
        6   => Some(Key::_5),
        7   => Some(Key::_6),
        8   => Some(Key::_7),
        9   => Some(Key::_8),
        10  => Some(Key::_9),
        11  => Some(Key::_0),
        14  => Some(Key::BackSpace),
        15  => Some(Key::Tab),
        28  => Some(Key::Enter),
        29  => Some(Key::LeftControl),
        30  => Some(Key::A),
        31  => Some(Key::S),
        32  => Some(Key::D),
        33  => Some(Key::F),
        34  => Some(Key::G),
        35  => Some(Key::H),
        36  => Some(Key::J),
        37  => Some(Key::K),
        38  => Some(Key::L),
        42  => Some(Key::LeftShift),
        44  => Some(Key::Z),
        45  => Some(Key::X),
        46  => Some(Key::C),
        47  => Some(Key::V),
        48  => Some(Key::B),
        49  => Some(Key::N),
        50  => Some(Key::M),
        54  => Some(Key::RightShift),
        56  => Some(Key::LeftAlt),
        57  => Some(Key::Space),
        58  => Some(Key::CapsLock),
        59  => Some(Key::F1),
        60  => Some(Key::F2),
        61  => Some(Key::F3),
        62  => Some(Key::F4),
        63  => Some(Key::F5),
        64  => Some(Key::F6),
        65  => Some(Key::F7),
        66  => Some(Key::F8),
        67  => Some(Key::F9),
        68  => Some(Key::F10),
        87  => Some(Key::F11),
        88  => Some(Key::F12),
        97  => Some(Key::RightControl),
        100 => Some(Key::RightAlt),
        102 => Some(Key::Home),
        103 => Some(Key::Up),
        104 => Some(Key::PageUp),
        105 => Some(Key::Left),
        106 => Some(Key::Right),
        107 => Some(Key::End),
        108 => Some(Key::Down),
        109 => Some(Key::PageDown),
        110 => Some(Key::Insert),
        111 => Some(Key::Delete),
        125 => Some(Key::LeftMeta),
        126 => Some(Key::RightMeta),
        _   => None,
    }
}

fn all_supported_keys() -> Vec<Key> {
    vec![
        Key::Esc,
        Key::_1, Key::_2, Key::_3, Key::_4, Key::_5,
        Key::_6, Key::_7, Key::_8, Key::_9, Key::_0,
        Key::BackSpace, Key::Tab, Key::Enter,
        Key::LeftControl, Key::RightControl,
        Key::LeftShift, Key::RightShift,
        Key::LeftAlt, Key::RightAlt,
        Key::LeftMeta, Key::RightMeta,
        Key::Space, Key::CapsLock,
        Key::A, Key::B, Key::C, Key::D, Key::E, Key::F, Key::G,
        Key::H, Key::I, Key::J, Key::K, Key::L, Key::M, Key::N,
        Key::O, Key::P, Key::Q, Key::R, Key::S, Key::T, Key::U,
        Key::V, Key::W, Key::X, Key::Y, Key::Z,
        Key::F1, Key::F2, Key::F3, Key::F4, Key::F5, Key::F6,
        Key::F7, Key::F8, Key::F9, Key::F10, Key::F11, Key::F12,
        Key::Home, Key::End, Key::PageUp, Key::PageDown,
        Key::Up, Key::Down, Key::Left, Key::Right,
        Key::Insert, Key::Delete,
    ]
}
