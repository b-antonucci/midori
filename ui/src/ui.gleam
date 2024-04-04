import config.{type Config, Config, Moveable}
import file.{A, B, C, D, E, F, G, H}
import gchessboard.{
  type Msg, NextTurn, Set, SetFen, SetMoveablePlayer, SetMoves, init, update,
  view,
}
import gleam/dict.{type Dict}
import gleam/dynamic.{type Dynamic}
import gleam/javascript/array.{type Array}
import gleam/list
import gleam/option.{None, Some}
import gleam/set
import gleam/string
import lustre.{type Action, type ClientSpa, application, component, dispatch}
import lustre/element
import position.{type Position, Position}
import rank.{Four, One, Three, Two}
import types.{type MoveData, White}

pub type Websocket

pub type ApplyMoveMessage {
  ApplyMoveMessage(move: String)
}

pub type UpdateGameResponse {
  UpdateGameResponse(moves: List(String), fen: String)
}

@external(javascript, "./ffi.js", "alert_js")
pub fn alert_js(message: Int) -> Nil

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

@external(javascript, "./ffi.js", "get_data_field_object_js")
pub fn get_data_field_object_js(object: String, field: String) -> String

pub fn main() {
  let socket = ws_init_js()
  // let on_attribute_change: Dict(String, fn(Dynamic) -> Result(Msg, List(_))) =
  //   dict.from_list([])
  // let board = component(init, update, view, on_attribute_change)
  let app = application(init, update, view)
  let assert Ok(interface) = lustre.start(app, "[gchessboard-lustre-app]", Nil)
  let on_message = fn(message) {
    case get_data_as_string_js(message) {
      "pong" -> {
        Nil
      }
      _some_data -> {
        let fen = get_data_field_js(message, "fen")
        let moves = get_data_field_object_js(message, "moves")

        case moves {
          "{}" -> {
            Nil
          }
          _ -> {
            // TODO: Move all the aggregating below into a function
            let moves_seperated_on_origin = string.split(moves, "],")
            let moves_seperate_origin_from_destination =
              list.map(moves_seperated_on_origin, fn(origin_dests_raw_string) {
                let origin_dests_split =
                  string.split(origin_dests_raw_string, ":")
                let assert Ok(origin_raw) = list.first(origin_dests_split)
                let origin = string.replace(origin_raw, "\"", "")
                let origin = string.replace(origin, "{", "")
                let assert Ok(dests_raw) = list.at(origin_dests_split, 1)
                let dests = string.replace(dests_raw, "[", "")
                #(origin, dests)
              })

            let #(promotions, moves_dests_seperated) =
              list.map_fold(
                moves_seperate_origin_from_destination,
                [],
                fn(acc, origin_dests) {
                  let origin = origin_dests.0
                  let dests = origin_dests.1
                  let dests_seperated = string.split(dests, ",")
                  let dests_seperated_cleaned =
                    list.map(dests_seperated, fn(dest) {
                      string.replace(dest, "\"", "")
                      |> string.replace("}", "")
                      |> string.replace("]", "")
                    })

                  // TODO: Are we doing extra work here by relying on the
                  // properties of Set to remove duplicates?
                  let promotions: set.Set(#(types.Origin, types.Destination)) =
                    list.fold(dests_seperated_cleaned, set.new(), fn(acc, dest) {
                      let position_dest =
                        position.from_string(string.slice(dest, 0, 2))

                      case string.slice(dest, 2, 1) {
                        "q" | "r" | "n" | "b" -> {
                          let origin = position.from_string(origin)
                          set.insert(acc, #(origin, position_dest))
                        }
                        _ -> acc
                      }
                    })
                  let promotions = set.to_list(promotions)

                  let dests_seperated_cleaned_promo_removed =
                    list.map(dests_seperated_cleaned, fn(dest) {
                      string.slice(dest, 0, 2)
                    })
                  #(list.append(acc, promotions), #(
                    origin,
                    dests_seperated_cleaned_promo_removed,
                  ))
                },
              )

            let moves_formatted: types.Moves =
              list.map(moves_dests_seperated, fn(origin_dests) {
                let origin = origin_dests.0
                let dests = origin_dests.1
                let origin_position = position.from_string(origin)
                let dest_positions =
                  list.map(dests, fn(dest) { position.from_string(dest) })
                #(origin_position, dest_positions)
              })

            let config =
              Config(
                moveable: Some(Moveable(
                  player: None,
                  promotions: Some(promotions),
                  fen: None,
                  after: None,
                  moves: None,
                )),
              )

            interface(dispatch(SetFen(fen)))
            interface(dispatch(NextTurn))
            interface(dispatch(SetMoves(Some(moves_formatted))))
            interface(dispatch(SetMoveablePlayer(Some(White))))
            interface(dispatch(Set(config)))
            Nil
          }
        }
      }
    }
  }

  ws_onmessage_js(socket, on_message)

  let after = fn(move_data) {
    let move_data: MoveData = move_data
    let from = position.to_string(move_data.from)
    let to = position.to_string(move_data.to)
    let promo = case move_data.promotion {
      True -> {
        "q"
      }
      False -> {
        ""
      }
    }
    let move = from <> "-" <> to <> promo
    ws_send_move_js(socket, ApplyMoveMessage(move))
    Nil
  }

  let config =
    Config(
      moveable: Some(Moveable(
        player: Some(White),
        promotions: None,
        fen: None,
        after: Some(after),
        moves: Some([
          #(Position(file: B, rank: One), [
            Position(file: A, rank: Three),
            Position(file: C, rank: Three),
          ]),
          #(Position(file: G, rank: One), [
            Position(file: F, rank: Three),
            Position(file: H, rank: Three),
          ]),
          #(Position(file: A, rank: Two), [
            Position(file: A, rank: Three),
            Position(file: A, rank: Four),
          ]),
          #(Position(file: B, rank: Two), [
            Position(file: B, rank: Three),
            Position(file: B, rank: Four),
          ]),
          #(Position(file: C, rank: Two), [
            Position(file: C, rank: Three),
            Position(file: C, rank: Four),
          ]),
          #(Position(file: D, rank: Two), [
            Position(file: D, rank: Three),
            Position(file: D, rank: Four),
          ]),
          #(Position(file: E, rank: Two), [
            Position(file: E, rank: Three),
            Position(file: E, rank: Four),
          ]),
          #(Position(file: F, rank: Two), [
            Position(file: F, rank: Three),
            Position(file: F, rank: Four),
          ]),
          #(Position(file: G, rank: Two), [
            Position(file: G, rank: Three),
            Position(file: G, rank: Four),
          ]),
          #(Position(file: H, rank: Two), [
            Position(file: H, rank: Three),
            Position(file: H, rank: Four),
          ]),
        ]),
      )),
    )

  interface(dispatch(Set(config)))

  Nil
}
