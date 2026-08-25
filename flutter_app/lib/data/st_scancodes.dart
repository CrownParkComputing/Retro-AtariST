// Atari ST keyboard scan codes, and the mapping from Flutter's logical keys.
//
// The ST's keyboard is handled by its own microcontroller (the IKBD, an HD6301
// running Atari's firmware) which sends a MAKE code when a key goes down and
// the same code with bit 7 set when it comes up. Games read those codes
// directly rather than going through TOS, which is why the whole input path in
// this app is in scan codes: anything higher-level -- a character, a Flutter
// LogicalKeyboardKey -- has no break half, and a game that never sees the
// break for "left" runs with the joystick held over until it is reset.
//
// The bridge sends only the make code; it sets bit 7 itself on release.
//
// The layout below is the UK/US ST keyboard. The physical positions are what
// matter for games (a game reading "the key left of Z" does not care what is
// printed on it), so this is a POSITIONAL map, not a character one.
import 'package:flutter/services.dart';

class StScancode {
  StScancode._();

  static const int escape = 0x01;
  static const int key1 = 0x02;
  static const int key2 = 0x03;
  static const int key3 = 0x04;
  static const int key4 = 0x05;
  static const int key5 = 0x06;
  static const int key6 = 0x07;
  static const int key7 = 0x08;
  static const int key8 = 0x09;
  static const int key9 = 0x0A;
  static const int key0 = 0x0B;
  static const int minus = 0x0C;
  static const int equals = 0x0D;
  static const int backspace = 0x0E;
  static const int tab = 0x0F;

  static const int q = 0x10;
  static const int w = 0x11;
  static const int e = 0x12;
  static const int r = 0x13;
  static const int t = 0x14;
  static const int y = 0x15;
  static const int u = 0x16;
  static const int i = 0x17;
  static const int o = 0x18;
  static const int p = 0x19;
  static const int bracketLeft = 0x1A;
  static const int bracketRight = 0x1B;
  static const int enter = 0x1C;
  static const int control = 0x1D;

  static const int a = 0x1E;
  static const int s = 0x1F;
  static const int d = 0x20;
  static const int f = 0x21;
  static const int g = 0x22;
  static const int h = 0x23;
  static const int j = 0x24;
  static const int k = 0x25;
  static const int l = 0x26;
  static const int semicolon = 0x27;
  static const int quote = 0x28;
  static const int backquote = 0x29;
  static const int leftShift = 0x2A;
  static const int backslash = 0x2B;

  static const int z = 0x2C;
  static const int x = 0x2D;
  static const int c = 0x2E;
  static const int v = 0x2F;
  static const int b = 0x30;
  static const int n = 0x31;
  static const int m = 0x32;
  static const int comma = 0x33;
  static const int period = 0x34;
  static const int slash = 0x35;
  static const int rightShift = 0x36;
  static const int alternate = 0x38;
  static const int space = 0x39;
  static const int capsLock = 0x3A;

  static const int f1 = 0x3B;
  static const int f2 = 0x3C;
  static const int f3 = 0x3D;
  static const int f4 = 0x3E;
  static const int f5 = 0x3F;
  static const int f6 = 0x40;
  static const int f7 = 0x41;
  static const int f8 = 0x42;
  static const int f9 = 0x43;
  static const int f10 = 0x44;

  /// The ST's own cluster: HELP and UNDO sit above the cursor keys, and a
  /// good number of games use UNDO as "quit to menu" or as a second pause.
  static const int help = 0x62;
  static const int undo = 0x61;
  static const int insert = 0x52;
  static const int home = 0x47;
  static const int delete = 0x53;

  static const int arrowUp = 0x48;
  static const int arrowLeft = 0x4B;
  static const int arrowRight = 0x4D;
  static const int arrowDown = 0x50;

  static const int numpadLeftParen = 0x63;
  static const int numpadRightParen = 0x64;
  static const int numpadDivide = 0x65;
  static const int numpadMultiply = 0x66;
  static const int numpad7 = 0x67;
  static const int numpad8 = 0x68;
  static const int numpad9 = 0x69;
  static const int numpadMinus = 0x4A;
  static const int numpad4 = 0x6A;
  static const int numpad5 = 0x6B;
  static const int numpad6 = 0x6C;
  static const int numpadPlus = 0x4E;
  static const int numpad1 = 0x6D;
  static const int numpad2 = 0x6E;
  static const int numpad3 = 0x6F;
  static const int numpad0 = 0x70;
  static const int numpadPeriod = 0x71;
  static const int numpadEnter = 0x72;

  /// Flutter physical key -> ST scan code.
  ///
  /// Keyed on PhysicalKeyboardKey, not LogicalKeyboardKey, and that is the
  /// whole point: a game asking for "the key under your left middle finger"
  /// must land on the same ST key whether the host keyboard is QWERTY, AZERTY
  /// or Dvorak. Logical keys would move it.
  /// Not const: PhysicalKeyboardKey overrides == and hashCode, and Dart
  /// forbids such a type as a const map key (the compiler cannot canonicalise
  /// the map without running user code).
  static final Map<PhysicalKeyboardKey, int> fromPhysical =
      <PhysicalKeyboardKey, int>{
    PhysicalKeyboardKey.escape: escape,
    PhysicalKeyboardKey.digit1: key1,
    PhysicalKeyboardKey.digit2: key2,
    PhysicalKeyboardKey.digit3: key3,
    PhysicalKeyboardKey.digit4: key4,
    PhysicalKeyboardKey.digit5: key5,
    PhysicalKeyboardKey.digit6: key6,
    PhysicalKeyboardKey.digit7: key7,
    PhysicalKeyboardKey.digit8: key8,
    PhysicalKeyboardKey.digit9: key9,
    PhysicalKeyboardKey.digit0: key0,
    PhysicalKeyboardKey.minus: minus,
    PhysicalKeyboardKey.equal: equals,
    PhysicalKeyboardKey.backspace: backspace,
    PhysicalKeyboardKey.tab: tab,
    PhysicalKeyboardKey.keyQ: q,
    PhysicalKeyboardKey.keyW: w,
    PhysicalKeyboardKey.keyE: e,
    PhysicalKeyboardKey.keyR: r,
    PhysicalKeyboardKey.keyT: t,
    PhysicalKeyboardKey.keyY: y,
    PhysicalKeyboardKey.keyU: u,
    PhysicalKeyboardKey.keyI: i,
    PhysicalKeyboardKey.keyO: o,
    PhysicalKeyboardKey.keyP: p,
    PhysicalKeyboardKey.bracketLeft: bracketLeft,
    PhysicalKeyboardKey.bracketRight: bracketRight,
    PhysicalKeyboardKey.enter: enter,
    PhysicalKeyboardKey.controlLeft: control,
    PhysicalKeyboardKey.controlRight: control,
    PhysicalKeyboardKey.keyA: a,
    PhysicalKeyboardKey.keyS: s,
    PhysicalKeyboardKey.keyD: d,
    PhysicalKeyboardKey.keyF: f,
    PhysicalKeyboardKey.keyG: g,
    PhysicalKeyboardKey.keyH: h,
    PhysicalKeyboardKey.keyJ: j,
    PhysicalKeyboardKey.keyK: k,
    PhysicalKeyboardKey.keyL: l,
    PhysicalKeyboardKey.semicolon: semicolon,
    PhysicalKeyboardKey.quote: quote,
    PhysicalKeyboardKey.backquote: backquote,
    PhysicalKeyboardKey.shiftLeft: leftShift,
    PhysicalKeyboardKey.backslash: backslash,
    PhysicalKeyboardKey.keyZ: z,
    PhysicalKeyboardKey.keyX: x,
    PhysicalKeyboardKey.keyC: c,
    PhysicalKeyboardKey.keyV: v,
    PhysicalKeyboardKey.keyB: b,
    PhysicalKeyboardKey.keyN: n,
    PhysicalKeyboardKey.keyM: m,
    PhysicalKeyboardKey.comma: comma,
    PhysicalKeyboardKey.period: period,
    PhysicalKeyboardKey.slash: slash,
    PhysicalKeyboardKey.shiftRight: rightShift,
    // Both host Alt keys go to the ST's single ALTERNATE. The ST had no
    // right-hand Alt, and leaving one unmapped means a user whose habit is
    // the right one finds it silently dead.
    PhysicalKeyboardKey.altLeft: alternate,
    PhysicalKeyboardKey.altRight: alternate,
    PhysicalKeyboardKey.space: space,
    PhysicalKeyboardKey.capsLock: capsLock,
    PhysicalKeyboardKey.f1: f1,
    PhysicalKeyboardKey.f2: f2,
    PhysicalKeyboardKey.f3: f3,
    PhysicalKeyboardKey.f4: f4,
    PhysicalKeyboardKey.f5: f5,
    PhysicalKeyboardKey.f6: f6,
    PhysicalKeyboardKey.f7: f7,
    PhysicalKeyboardKey.f8: f8,
    PhysicalKeyboardKey.f9: f9,
    PhysicalKeyboardKey.f10: f10,
    PhysicalKeyboardKey.arrowUp: arrowUp,
    PhysicalKeyboardKey.arrowDown: arrowDown,
    PhysicalKeyboardKey.arrowLeft: arrowLeft,
    PhysicalKeyboardKey.arrowRight: arrowRight,
    PhysicalKeyboardKey.home: home,
    PhysicalKeyboardKey.insert: insert,
    PhysicalKeyboardKey.delete: delete,
    // F11/F12 have no ST equivalent, so they carry HELP and UNDO -- the two
    // ST keys with nowhere else to sit on a PC keyboard.
    PhysicalKeyboardKey.f11: help,
    PhysicalKeyboardKey.f12: undo,
    PhysicalKeyboardKey.numpad0: numpad0,
    PhysicalKeyboardKey.numpad1: numpad1,
    PhysicalKeyboardKey.numpad2: numpad2,
    PhysicalKeyboardKey.numpad3: numpad3,
    PhysicalKeyboardKey.numpad4: numpad4,
    PhysicalKeyboardKey.numpad5: numpad5,
    PhysicalKeyboardKey.numpad6: numpad6,
    PhysicalKeyboardKey.numpad7: numpad7,
    PhysicalKeyboardKey.numpad8: numpad8,
    PhysicalKeyboardKey.numpad9: numpad9,
    PhysicalKeyboardKey.numpadDecimal: numpadPeriod,
    PhysicalKeyboardKey.numpadAdd: numpadPlus,
    PhysicalKeyboardKey.numpadSubtract: numpadMinus,
    PhysicalKeyboardKey.numpadMultiply: numpadMultiply,
    PhysicalKeyboardKey.numpadDivide: numpadDivide,
    PhysicalKeyboardKey.numpadEnter: numpadEnter,
  };

  /// The rows of the on-screen keyboard, as (label, scan code) pairs.
  ///
  /// Laid out as the ST's own keyboard rather than as a phone keyboard: this
  /// is used to type things like a game's copy-protection answer or a
  /// cheat-mode key sequence, both of which are documented in terms of where
  /// the key is on an ST.
  static const List<List<(String, int)>> onScreenRows = [
    [
      ('ESC', escape), ('1', key1), ('2', key2), ('3', key3), ('4', key4),
      ('5', key5), ('6', key6), ('7', key7), ('8', key8), ('9', key9),
      ('0', key0), ('-', minus), ('=', equals), ('BS', backspace),
    ],
    [
      ('TAB', tab), ('Q', q), ('W', w), ('E', e), ('R', r), ('T', t),
      ('Y', y), ('U', u), ('I', i), ('O', o), ('P', p),
      ('[', bracketLeft), (']', bracketRight),
    ],
    [
      ('CTRL', control), ('A', a), ('S', s), ('D', d), ('F', f), ('G', g),
      ('H', h), ('J', j), ('K', k), ('L', l), (';', semicolon),
      ("'", quote), ('RET', enter),
    ],
    [
      ('SHIFT', leftShift), ('Z', z), ('X', x), ('C', c), ('V', v),
      ('B', b), ('N', n), ('M', m), (',', comma), ('.', period),
      ('/', slash), ('SHIFT', rightShift),
    ],
    [
      ('ALT', alternate), ('SPACE', space), ('HELP', help), ('UNDO', undo),
    ],
  ];
}
