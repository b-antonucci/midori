import gleam/json.{array, object, string as json_string}
import gleam/list
import midori/uci_move

// The first element of the tuple is the origin square
// and the second element is a list of possible destination squares
pub type ClientFormatMoveList {
  ClientFormatMoveList(moves: List(#(String, List(String))))
}

pub type ClientWebsocketMessage {
  ConfirmMove(move: uci_move.UciMove)
  BotMove(moves: ClientFormatMoveList, fen: String)
}

pub fn update_game_message_to_json(
  update_game_message: ClientWebsocketMessage,
) -> String {
  case update_game_message {
    ConfirmMove(move) -> {
      object([#("move", json_string(move))])
      |> json.to_string
    }
    BotMove(moves, fen) -> {
      let moves = moves.moves
      let moves_with_json_dests =
        list.map(moves, fn(move) { #(move.0, array(move.1, of: json_string)) })
      object([
        #("moves", object(moves_with_json_dests)),
        #("fen", json_string(fen)),
      ])
      |> json.to_string
    }
  }
}
