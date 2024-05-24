import config.{type Config, Config, Moveable}
import gchessboard.{
  NextTurn, Set, SetFen, SetMoves, SetPromotions, ToggleVisibility, init, update,
  view,
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
import types.{type MoveData, type Origin, White}

pub type Websocket

pub type ApplyMoveMessage {
  ApplyMoveMessage(move: String)
}

pub type RequestGameDataMessage {
  RequestGameDataMessage(game_id: String)
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
    mode: UiMode,
    lobby_mode_settings: LobbyModeSettings,
    game_mode_settings: GameModeSettings,
  )
}

pub type UiMode {
  LobbyMode
  GameMode
}

pub type LobbyModeSettings {
  LobbyModeSettings(
    on_computer_game_confirmation: Option(
      fn(String, Array(Array(String))) -> Nil,
    ),
  )
}

pub type GameModeSettings {
  GameModeSettings(
    promotion: Bool,
    promotion_on_click: Option(
      fn(PromotionMenuClickData, Position, Position) -> Nil,
    ),
    from: Option(Position),
    to: Option(Position),
  )
}

pub type UiMsg {
  ChangeMode(UiMode)
  ShowPromotion(from: Position, to: Position)
  CallOnClick(PromotionMenuOptions)
  SetOnClick(fn(PromotionMenuClickData, Position, Position) -> Nil)
  RequestGameWithComputer
  SetRequestGameWithComputerConfirmation(
    fn(String, Array(Array(String))) -> Nil,
  )
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

@external(javascript, "./ffi.js", "ws_send_game_data_request_js")
pub fn ws_send_game_data_request_js(
  socket: Websocket,
  message: RequestGameDataMessage,
) -> Nil

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

@external(javascript, "./ffi.js", "request_game_with_computer_js")
pub fn request_game_with_computer_js(
  callback: fn(String, Array(Array(String))) -> Nil,
) -> Nil

@external(javascript, "./ffi.js", "url_pathname_js")
pub fn url_pathname_js() -> String

pub fn main() {
  let socket = ws_init_js()
  let app = application(init, update, view)
  let url_pathname = url_pathname_js()

  let assert Ok(interface) = lustre.start(app, "[gchessboard-lustre-app]", Nil)

  let ui_mode = case url_pathname {
    "/game/" <> game_id -> {
      interface(dispatch(ToggleVisibility))
      // TODO: this NextTurn Dispatch is a hack because the on_message function calls
      // this same dispatch since it assumes that the arrival of a move signifies a change
      // of turns. That is not the case here since we are getting state of the game, and not
      // the response to one of our moves. The solution that comes to mind is a "SetTurn" 
      // message.
      interface(dispatch(NextTurn))
      ws_send_game_data_request_js(
        socket,
        RequestGameDataMessage(game_id: game_id),
      )
      GameMode
    }
    _ -> {
      LobbyMode
    }
  }
  let ui_app = application(ui_init(_, ui_mode), ui_update, ui_view)
  let assert Ok(ui_interface) = lustre.start(ui_app, "[ui-lustre-app]", Nil)

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
        moves: None,
      )),
    )

  interface(dispatch(Set(config)))

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
                panic as "Invalid move set"
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
                    panic as "Invalid destination"
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

  let on_computer_game_confirmation = fn(
    fen: String,
    moves: Array(Array(String)),
  ) {
    let moves_list = array.to_list(moves)
    let #(moves, promo_moves) =
      list.fold(moves_list, #([], []), fn(acc, item) {
        let move_set_list = array.to_list(item)
        let assert Ok(origin) = list.first(move_set_list)
        let destinations = case move_set_list {
          [_, ..destinations] -> {
            destinations
          }
          _ -> {
            panic as "Invalid move set"
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
                panic as "Invalid destination"
              }
            }
          })
        #(
          list.prepend(acc.0, #(origin, destinations)),
          list.append(acc.1, dict.to_list(promo_destinations)),
        )
      })

    ui_interface(dispatch(ChangeMode(GameMode)))
    interface(dispatch(ToggleVisibility))
    interface(dispatch(SetFen(fen)))
    interface(dispatch(SetMoves(moves)))
    interface(dispatch(SetPromotions(promo_moves)))
  }

  ui_interface(
    dispatch(SetRequestGameWithComputerConfirmation(
      on_computer_game_confirmation,
    )),
  )

  Nil
}

pub fn ui_init(_, ui_mode: UiMode) {
  let game_mode_settings =
    GameModeSettings(
      promotion: False,
      promotion_on_click: None,
      from: None,
      to: None,
    )
  let lobby_mode_settings = LobbyModeSettings(None)
  #(UiState(ui_mode, lobby_mode_settings, game_mode_settings), effect.none())
}

pub fn ui_update(state: UiState, msg) {
  case msg {
    ChangeMode(mode) -> {
      #(
        UiState(
          mode: mode,
          lobby_mode_settings: state.lobby_mode_settings,
          game_mode_settings: state.game_mode_settings,
        ),
        effect.none(),
      )
    }
    ShowPromotion(from, to) -> {
      case state.mode {
        GameMode -> {
          #(
            UiState(
              mode: GameMode,
              lobby_mode_settings: state.lobby_mode_settings,
              game_mode_settings: GameModeSettings(
                promotion: True,
                from: Some(from),
                to: Some(to),
                promotion_on_click: state.game_mode_settings.promotion_on_click,
              ),
            ),
            effect.none(),
          )
        }
        _ -> {
          #(state, effect.none())
        }
      }
    }
    CallOnClick(promo_menu_choice) -> {
      case state.mode {
        GameMode -> {
          let assert GameModeSettings(
            _promotion,
            Some(promotion_on_click),
            Some(from),
            Some(to),
          ) = state.game_mode_settings
          promotion_on_click(
            PromotionMenuClickData(promotion: promo_menu_choice),
            from,
            to,
          )
          #(
            UiState(
              mode: state.mode,
              lobby_mode_settings: state.lobby_mode_settings,
              game_mode_settings: GameModeSettings(
                promotion: False,
                from: None,
                to: None,
                promotion_on_click: Some(promotion_on_click),
              ),
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
          mode: state.mode,
          lobby_mode_settings: state.lobby_mode_settings,
          game_mode_settings: GameModeSettings(
            promotion: state.game_mode_settings.promotion,
            promotion_on_click: Some(on_click),
            from: state.game_mode_settings.from,
            to: state.game_mode_settings.to,
          ),
        ),
        effect.none(),
      )
    }
    RequestGameWithComputer -> {
      case state.mode {
        LobbyMode -> {
          let assert Some(on_computer_game_confirmation) =
            state.lobby_mode_settings.on_computer_game_confirmation
          request_game_with_computer_js(on_computer_game_confirmation)
          #(state, effect.none())
        }
        _ -> {
          #(state, effect.none())
        }
      }
    }
    SetRequestGameWithComputerConfirmation(on_computer_game_confirmation) -> {
      case state.mode {
        LobbyMode -> {
          #(
            UiState(
              mode: state.mode,
              lobby_mode_settings: LobbyModeSettings(Some(
                on_computer_game_confirmation,
              )),
              game_mode_settings: state.game_mode_settings,
            ),
            effect.none(),
          )
        }
        _ -> {
          #(state, effect.none())
        }
      }
    }
  }
}

pub fn ui_view(state: UiState) {
  case state.mode {
    GameMode -> {
      let show_promotion = state.game_mode_settings.promotion

      case show_promotion {
        True -> {
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
        False -> {
          div([], [])
        }
      }
    }
    LobbyMode -> {
      div([], [
        html.button([event.on("click", fn(_) { Ok(RequestGameWithComputer) })], [
          text("PLAY WITH THE COMPUTER"),
        ]),
      ])
    }
  }
}
