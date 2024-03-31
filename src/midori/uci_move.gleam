import gleam/string

// TODO: uci move format should be encoded with types instead of a plain string
pub type UciMove {
  UciMove(move: String)
}

// we receive a string in the following format: "e2e4"
// we need to convert it to a UciMove
pub fn convert_move(move: String) -> UciMove {
  case string.split(move, "-") {
    [from, to] -> {
      let move = from <> to
      UciMove(move)
    }
    _ -> panic("Invalid move format")
  }
}
