import config.{type Config, Config, Moveable}
import file.{A, B, C, D, E, F, G, H}
import gchessboard.{
  NextTurn, Set, SetFen, SetMoves, SetPromotions, init, update, view,
}
import gleam/dict
import gleam/javascript/array.{type Array}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import lustre.{application, dispatch}
import lustre/effect
import lustre/element/html.{div, text}
import lustre/event
import position.{type Position, Position, from_string}
import rank.{Four, One, Three, Two}
import types.{type MoveData, type Origin, White}

pub type Websocket

pub type ApplyMoveMessage {
  ApplyMoveMessage(move: String)
}

pub type UpdateGameResponse {
  UpdateGameResponse(moves: List(String), fen: String)
}

pub type PromotionMenuOptions {
  Queen
  Rook
  Knight
  Bishop
}

pub type PromotionMenuClickData {
  PromotionMenuClickData(promotion: PromotionMenuOptions)
}

pub type UiState {
  UiState(
    promotion: Bool,
    on_click: Option(fn(PromotionMenuClickData, Position, Position) -> Nil),
    from: Option(Position),
    to: Option(Position),
  )
}

pub type UiMsg {
  ShowPromotion(from: Position, to: Position)
  CallOnClick(PromotionMenuOptions)
  SetOnClick(fn(PromotionMenuClickData, Position, Position) -> Nil)
}

@external(javascript, "./ffi.js", "console_log_js")
pub fn console_log_js_ui_state(message: UiState) -> Nil

@external(javascript, "./ffi.js", "alert_js")
pub fn alert_js_int(message: Int) -> Nil

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

@external(javascript, "./ffi.js", "get_data_field_object_as_array_js")
pub fn get_data_field_object_as_array_js(
  object: String,
  field: String,
) -> Array(Array(String))

pub fn main() {
  let socket = ws_init_js()
  let app = application(init, update, view)
  let ui_app = application(ui_init, ui_update, ui_view)
  let assert Ok(interface) = lustre.start(app, "[gchessboard-lustre-app]", Nil)
  let assert Ok(ui_interface) = lustre.start(ui_app, "[ui-lustre-app]", Nil)
  let on_message = fn(message) {
    case get_data_as_string_js(message) {
      "pong" -> {
        Nil
      }
      "{\"moves\":" <> _ -> {
        let moves_array = get_data_field_object_as_array_js(message, "moves")
        let fen = get_data_field_js(message, "fen")
        let moves_list = array.to_list(moves_array)
        let #(moves, promo_moves) =
          list.fold(moves_list, #([], []), fn(acc, item) {
            let move_set_list = array.to_list(item)
            let assert Ok(origin) = list.first(move_set_list)
            let destinations = case move_set_list {
              [_, ..destinations] -> {
                destinations
              }
              _ -> {
                panic("Invalid move set")
              }
            }
            let origin: Origin = from_string(origin)
            let #(destinations, promo_destinations) =
              list.fold(destinations, #([], dict.new()), fn(acc, item) {
                case string.length(item) {
                  2 -> {
                    let destination = from_string(item)
                    #(list.prepend(acc.0, destination), acc.1)
                  }
                  3 -> {
                    let destination = from_string(string.slice(item, 0, 2))
                    #(
                      list.prepend(acc.0, destination),
                      // TODO: check if dict is empty first? is there a better way to do this?
                      dict.insert(acc.1, origin, destination),
                    )
                  }
                  _ -> {
                    panic("Invalid destination")
                  }
                }
              })
            #(
              list.prepend(acc.0, #(origin, destinations)),
              list.append(acc.1, dict.to_list(promo_destinations)),
            )
          })
        interface(dispatch(SetFen(fen)))
        interface(dispatch(SetMoves(moves)))
        interface(dispatch(SetPromotions(promo_moves)))
        interface(dispatch(NextTurn))
        Nil
      }
      _ws_message -> {
        let _move = get_data_field_js(message, "move")
        Nil
      }
    }
  }

  ws_onmessage_js(socket, on_message)

  let after = fn(move_data) {
    let move_data: MoveData = move_data

    case move_data.promotion {
      True -> {
        ui_interface(dispatch(ShowPromotion(move_data.from, move_data.to)))
      }
      False -> {
        let from = position.to_string(move_data.from)
        let to = position.to_string(move_data.to)
        let move = from <> "-" <> to
        ws_send_move_js(socket, ApplyMoveMessage(move))
      }
    }
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

  let after_promo_menu_click = fn(promo_menu_data, from, to) {
    let promo_menu_data: PromotionMenuClickData = promo_menu_data
    let from = position.to_string(from)
    let to = position.to_string(to)
    let move = case promo_menu_data.promotion {
      Queen -> {
        from <> "-" <> to <> "q"
      }
      Rook -> {
        from <> "-" <> to <> "r"
      }
      Knight -> {
        from <> "-" <> to <> "n"
      }
      Bishop -> {
        from <> "-" <> to <> "b"
      }
    }
    ws_send_move_js(socket, ApplyMoveMessage(move))
    Nil
  }

  ui_interface(dispatch(SetOnClick(after_promo_menu_click)))

  Nil
}

pub fn ui_init(_) {
  #(
    UiState(promotion: False, on_click: None, from: None, to: None),
    effect.none(),
  )
}

pub fn ui_update(state, msg) {
  case msg {
    ShowPromotion(from, to) -> {
      #(
        UiState(..state, promotion: True, from: Some(from), to: Some(to)),
        effect.none(),
      )
    }
    CallOnClick(promo_menu_choice) -> {
      case state {
        UiState(
            promotion: True,
            on_click: Some(on_click),
            from: Some(from),
            to: Some(to),
          ) -> {
          on_click(
            PromotionMenuClickData(promotion: promo_menu_choice),
            from,
            to,
          )
          #(
            UiState(
              promotion: False,
              on_click: state.on_click,
              from: None,
              to: None,
            ),
            effect.none(),
          )
        }
        _ -> {
          #(state, effect.none())
        }
      }
    }
    SetOnClick(on_click) -> {
      #(
        UiState(
          promotion: state.promotion,
          on_click: Some(on_click),
          from: state.from,
          to: state.to,
        ),
        effect.none(),
      )
    }
  }
}

pub fn ui_view(state) {
  case state {
    UiState(promotion: True, on_click: _, from: _from, to: _to) -> {
      div([], [
        html.button([event.on("click", fn(_) { Ok(CallOnClick(Queen)) })], [
          text("Queen"),
        ]),
        html.button([event.on("click", fn(_) { Ok(CallOnClick(Rook)) })], [
          text("Rook"),
        ]),
        html.button([event.on("click", fn(_) { Ok(CallOnClick(Knight)) })], [
          text("Knight"),
        ]),
        html.button([event.on("click", fn(_) { Ok(CallOnClick(Bishop)) })], [
          text("Bishop"),
        ]),
      ])
    }
    UiState(promotion: False, on_click: _, from: _, to: _) -> {
      div([], [])
    }
  }
}
