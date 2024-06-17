import color.{type Color}
import fen.{from_string}
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
  RequestGameData(moves: ClientFormatMoveList, fen: String, user_color: Color)
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
    RequestGameData(moves, fen, user_color) -> {
      // TODO: this needs to be labeled as a response to a game data request
      let user_color = case user_color {
        color.White -> "white"
        color.Black -> "black"
      }
      let turn = from_string(fen).turn
      let is_user_turn = case turn {
        color.White -> user_color == "white"
        color.Black -> user_color == "black"
      }
      let moves = case is_user_turn {
        True -> {
          moves.moves
        }
        False -> []
      }
      let turn_string = case turn {
        color.White -> "white"
        color.Black -> "black"
      }
      let moves_with_json_dests =
        list.map(moves, fn(move) { #(move.0, array(move.1, of: json_string)) })
      object([
        #("type", json_string("request_game_data_response")),
        #("moves", object(moves_with_json_dests)),
        #("fen", json_string(fen)),
        #("user_color", json_string(user_color)),
        #("turn", json_string(turn_string)),
      ])
      |> json.to_string
    }
  }
}
