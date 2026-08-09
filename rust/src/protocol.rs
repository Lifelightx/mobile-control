/// Binary packet protocol — mirrors Flutter BinaryEncoder exactly.
///
/// Header layout (12 bytes):
///   [0]    u8   Version
///   [1]    u8   Opcode
///   [2-3]  u16  Sequence  (big-endian)
///   [4-7]  u32  Timestamp (big-endian, milliseconds)
///   [8-11] u32  Payload length (big-endian)
///   [12..] Payload bytes

use anyhow::{bail, Result};

pub const HEADER_SIZE: usize = 12;
pub const VERSION: u8 = 1;

#[repr(u8)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Opcode {
    MouseMove   = 0x01,
    MouseDown   = 0x02,
    MouseUp     = 0x03,
    MouseScroll = 0x04,
    KeyDown     = 0x05,
    KeyUp       = 0x06,
}

impl TryFrom<u8> for Opcode {
    type Error = anyhow::Error;
    fn try_from(v: u8) -> Result<Self> {
        match v {
            0x01 => Ok(Opcode::MouseMove),
            0x02 => Ok(Opcode::MouseDown),
            0x03 => Ok(Opcode::MouseUp),
            0x04 => Ok(Opcode::MouseScroll),
            0x05 => Ok(Opcode::KeyDown),
            0x06 => Ok(Opcode::KeyUp),
            _    => bail!("Unknown opcode: {:#04x}", v),
        }
    }
}

#[derive(Debug)]
pub struct InputPacket {
    pub version:    u8,
    pub opcode:     Opcode,
    pub sequence:   u16,
    pub timestamp:  u32,
    pub payload:    Vec<u8>,
}

/// Mouse button codes (sent as 1-byte payload on MouseDown / MouseUp).
pub mod button {
    pub const LEFT:   u8 = 0;
    pub const RIGHT:  u8 = 1;
    pub const MIDDLE: u8 = 2;
}

impl InputPacket {
    /// Decode a raw byte slice into an InputPacket.
    pub fn decode(data: &[u8]) -> Result<Self> {
        if data.len() < HEADER_SIZE {
            bail!("Packet too small: {} bytes", data.len());
        }

        let version        = data[0];
        let opcode         = Opcode::try_from(data[1])?;
        let sequence       = u16::from_be_bytes([data[2], data[3]]);
        let timestamp      = u32::from_be_bytes([data[4], data[5], data[6], data[7]]);
        let payload_len    = u32::from_be_bytes([data[8], data[9], data[10], data[11]]) as usize;

        if version != VERSION {
            bail!("Unsupported version: {}", version);
        }

        let total = HEADER_SIZE + payload_len;
        if data.len() < total {
            bail!("Incomplete packet: need {} bytes, got {}", total, data.len());
        }

        let payload = data[HEADER_SIZE..total].to_vec();

        Ok(InputPacket { version, opcode, sequence, timestamp, payload })
    }

    /// Parse the mouse-move payload: (i16 dx, i16 dy).
    pub fn parse_mouse_move(&self) -> Result<(i16, i16)> {
        if self.payload.len() < 4 {
            bail!("MouseMove payload too short");
        }
        let dx = i16::from_be_bytes([self.payload[0], self.payload[1]]);
        let dy = i16::from_be_bytes([self.payload[2], self.payload[3]]);
        Ok((dx, dy))
    }

    /// Parse mouse-button payload: u8 button id.
    pub fn parse_mouse_button(&self) -> Result<u8> {
        if self.payload.is_empty() {
            bail!("MouseButton payload empty");
        }
        Ok(self.payload[0])
    }

    /// Parse scroll payload: (i16 dx, i16 dy).
    pub fn parse_scroll(&self) -> Result<(i16, i16)> {
        if self.payload.len() < 4 {
            bail!("Scroll payload too short");
        }
        let dx = i16::from_be_bytes([self.payload[0], self.payload[1]]);
        let dy = i16::from_be_bytes([self.payload[2], self.payload[3]]);
        Ok((dx, dy))
    }

    /// Parse key payload: u16 linux keycode.
    pub fn parse_key(&self) -> Result<u16> {
        if self.payload.len() < 2 {
            bail!("Key payload too short");
        }
        Ok(u16::from_be_bytes([self.payload[0], self.payload[1]]))
    }
}
