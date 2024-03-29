import gleam/string
import gleam/int

pub type UciMove {
  UciMove(move: String)
}

// we receive a string in the following format: "12-20" which represents "e2e4"
// we need to convert it to a UciMove
pub fn convert_move(move: String) -> UciMove {
  case string.split(move, "-") {
    [from, to] -> {
      let from = int.parse(from)
      let to = int.parse(to)
      case [from, to] {
        [Ok(from), Ok(to)] -> {
          let from_rank = { from / 8 } + 1
          let from_rank_as_string = int.to_string(from_rank)
          let from_file = from % 8
          let from_file = case from_file {
            0 -> "a"
            1 -> "b"
            2 -> "c"
            3 -> "d"
            4 -> "e"
            5 -> "f"
            6 -> "g"
            7 -> "h"
            _ -> panic("Invalid move format")
          }
          let to_rank = { to / 8 } + 1
          let to_rank_as_string = int.to_string(to_rank)
          let to_file = to % 8
          let to_file = case to_file {
            0 -> "a"
            1 -> "b"
            2 -> "c"
            3 -> "d"
            4 -> "e"
            5 -> "f"
            6 -> "g"
            7 -> "h"
            _ -> panic("Invalid move format")
          }
          UciMove(
            move: from_file
              <> from_rank_as_string
              <> to_file
              <> to_rank_as_string,
          )
        }
        _ -> panic("Invalid move format")
      }
    }
    _ -> panic("Invalid move format")
  }
}
