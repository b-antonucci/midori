import position.{Position}
import rank.{Four, One, Three, Two}
import file.{A, B, C, D, E, F, G, H}
import types.{type MoveData, White}
import config.{type Config, Config, Moveable}
import gleam/option.{None, Some}
import gleam/int
import gleam/list
import gleam/string
import gleam/dict
import lustre.{application}
import gchessboard.{
  NextTurn, Set, SetFen, SetMoveablePlayer, SetMoves, init, update, view,
}
import gleam/javascript/array.{type Array, to_list}

pub type Websocket

pub type ApplyMoveMessage {
  ApplyMoveMessage(move: String)
}

pub type UpdateGameResponse {
  UpdateGameResponse(moves: List(String), fen: String)
}

@external(javascript, "./ffi.js", "alert_js")
pub fn alert_js(message: String) -> Nil

@external(javascript, "./ffi.js", "alert_js")
pub fn alert_js_string(message: String) -> Nil

@external(javascript, "./ffi.js", "alert_js_object_data")
pub fn alert_js_object_data(message: String) -> Nil

@external(javascript, "./ffi.js", "ws_onmessage_js")
pub fn ws_onmessage_js(socket: Websocket, callback: fn(String) -> Nil) -> Nil

@external(javascript, "./ffi.js", "ws_onopen_js")
pub fn ws_onopen_js(socket: Websocket, callback: fn() -> Nil) -> Nil

@external(javascript, "./ffi.js", "ws_onclose_js")
pub fn ws_onclose_js(socket: Websocket, callback: fn() -> Nil) -> Nil

@external(javascript, "./ffi.js", "ws_onerror_js")
pub fn ws_onerror_js(socket: Websocket, callback: fn() -> Nil) -> Nil

@external(javascript, "./ffi.js", "ws_send_move_js")
pub fn ws_send_move_js(socket: Websocket, message: ApplyMoveMessage) -> Nil

@external(javascript, "./ffi.js", "ws_init_js")
pub fn ws_init_js() -> Websocket

@external(javascript, "./ffi.js", "get_data_as_string_js")
pub fn get_data_as_string_js(object: String) -> String

@external(javascript, "./ffi.js", "get_data_field_js")
pub fn get_data_field_js(object: String, field: String) -> String

@external(javascript, "./ffi.js", "get_data_field_array_js")
pub fn get_data_field_array_js(object: String, field: String) -> Array(String)

pub fn main() {
  let socket = ws_init_js()
  let app = application(init, update, view)
  let assert Ok(interface) = lustre.start(app, "[data-lustre-app]", Nil)
  let on_message = fn(message) {
    case get_data_as_string_js(message) {
      "pong" -> {
        Nil
      }
      _some_data -> {
        let fen = get_data_field_js(message, "fen")
        let moves = get_data_field_array_js(message, "moves")
        let moves = to_list(moves)

        let moves =
          list.map(moves, fn(move) {
            case string.length(move) {
              4 -> {
                [string.slice(move, 0, 2), string.slice(move, 2, 2)]
              }
              5 -> {
                [
                  string.slice(move, 0, 2),
                  string.slice(move, 2, 2),
                  string.slice(move, 4, 2),
                ]
              }
              _ -> panic("Invalid move length")
            }
          })

        let formatted_moves =
          list.fold(moves, dict.new(), fn(acc, move) {
            let acc = case move {
              [from, to] -> {
                let from = types.Origin(origin: position.from_string(from))
                let to = position.from_string(to)
                case dict.get(acc, from) {
                  Error(_) ->
                    dict.insert(
                      acc,
                      from,
                      types.Destinations(destinations: [to]),
                    )
                  Ok(dests) ->
                    dict.insert(
                      acc,
                      from,
                      types.Destinations(destinations: [
                        to,
                        ..dests.destinations
                      ]),
                    )
                }
              }
              [from, to, _promotion] -> {
                let from = types.Origin(origin: position.from_string(from))
                let to = position.from_string(to)
                case dict.get(acc, from) {
                  Error(_) ->
                    dict.insert(
                      acc,
                      from,
                      types.Destinations(destinations: [to]),
                    )
                  Ok(dests) ->
                    dict.insert(
                      acc,
                      from,
                      types.Destinations(destinations: [
                        to,
                        ..dests.destinations
                      ]),
                    )
                }
              }
              _ -> panic("Invalid move length")
            }
            acc
          })

        let formatted_moves = dict.to_list(formatted_moves)
        interface(SetFen(fen))
        interface(NextTurn)
        interface(SetMoves(Some(types.Moves(moves: formatted_moves))))
        interface(SetMoveablePlayer(Some(White)))
        Nil
      }
    }
  }

  ws_onmessage_js(socket, on_message)

  let after = fn(move_data) {
    let move_data: MoveData = move_data
    let from = position.to_int(move_data.from)
    let to = position.to_int(move_data.to)
    let from_as_string = int.to_string(from)
    let to_as_string = int.to_string(to)
    let move = from_as_string <> "-" <> to_as_string

    ws_send_move_js(socket, ApplyMoveMessage(move))
    Nil
  }

  let config =
    Config(
      moveable: Some(Moveable(
        player: Some(White),
        fen: None,
        after: Some(after),
        moves: Some(
          types.Moves(moves: [
            #(
              types.Origin(origin: Position(file: B, rank: One)),
              types.Destinations(destinations: [
                Position(file: A, rank: Three),
                Position(file: C, rank: Three),
              ]),
            ),
            #(
              types.Origin(origin: Position(file: G, rank: One)),
              types.Destinations(destinations: [
                Position(file: F, rank: Three),
                Position(file: H, rank: Three),
              ]),
            ),
            #(
              types.Origin(origin: Position(file: A, rank: Two)),
              types.Destinations(destinations: [
                Position(file: A, rank: Three),
                Position(file: A, rank: Four),
              ]),
            ),
            #(
              types.Origin(origin: Position(file: B, rank: Two)),
              types.Destinations(destinations: [
                Position(file: B, rank: Three),
                Position(file: B, rank: Four),
              ]),
            ),
            #(
              types.Origin(origin: Position(file: C, rank: Two)),
              types.Destinations(destinations: [
                Position(file: C, rank: Three),
                Position(file: C, rank: Four),
              ]),
            ),
            #(
              types.Origin(origin: Position(file: D, rank: Two)),
              types.Destinations(destinations: [
                Position(file: D, rank: Three),
                Position(file: D, rank: Four),
              ]),
            ),
            #(
              types.Origin(origin: Position(file: E, rank: Two)),
              types.Destinations(destinations: [
                Position(file: E, rank: Three),
                Position(file: E, rank: Four),
              ]),
            ),
            #(
              types.Origin(origin: Position(file: F, rank: Two)),
              types.Destinations(destinations: [
                Position(file: F, rank: Three),
                Position(file: F, rank: Four),
              ]),
            ),
            #(
              types.Origin(origin: Position(file: G, rank: Two)),
              types.Destinations(destinations: [
                Position(file: G, rank: Three),
                Position(file: G, rank: Four),
              ]),
            ),
            #(
              types.Origin(origin: Position(file: H, rank: Two)),
              types.Destinations(destinations: [
                Position(file: H, rank: Three),
                Position(file: H, rank: Four),
              ]),
            ),
          ]),
        ),
      )),
    )

  interface(Set(config))

  Nil
}
