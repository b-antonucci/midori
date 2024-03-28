import position.{Position, to_int}
import rank.{Four, One, Three, Two}
import file.{A, B, C, D, E, F, G, H}
import types.{type MoveData, White}
import config.{type Config, Config, Moveable}
import gleam/option.{Some}
import gleam/int.{to_string}
import lustre.{application}
import gchessboard.{Set, init, update, view}

pub type Websocket

pub type ApplyMoveMessage {
  ApplyMoveMessage(move: String)
}

@external(javascript, "./ffi.js", "alert_js")
pub fn alert_js(message: Int) -> Nil

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

pub fn main() {
  let socket = ws_init_js()
  let app = application(init, update, view)
  let assert Ok(interface) = lustre.start(app, "[data-lustre-app]", Nil)

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
