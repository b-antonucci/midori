import config.{type Config, Config, Moveable}
import gchessboard.{
  type Msg, HideBoard, NextTurn, Set, SetFen, SetMoves, SetPromotions, SetTurn,
  ShowBoard, init, update, view,
}
import gleam/dict
import gleam/javascript/array.{type Array}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import lustre.{type Action, type ClientSpa, application, dispatch}
import lustre/attribute.{id}
import lustre/effect
import lustre/element/html.{div, text}
import lustre/event
import position.{type Position, Position, from_string}
import types.{
  type MoveData, type Origin, Black, BlackOriented, White, WhiteOriented,
}

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
    chessboard_interface: fn(Action(Msg, ClientSpa)) -> Nil,
  )
}

pub type UiMode {
  LobbyMode
  GameMode
}

pub type LobbyModeSettings {
  LobbyModeSettings(
    on_computer_game_request_click: Option(fn(String) -> Nil),
    computer_game_request_prompt_visibility: Bool,
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
  ShowRequestGameWithComputerPrompt
  RequestGameWithComputer(color: String)
  SetOnComputerGameRequestClick(fn(String) -> Nil)
}

@external(javascript, "./ffi.js", "alert_js")
pub fn alert_js_string(message: String) -> Nil

@external(javascript, "./ffi.js", "ws_onmessage_js")
pub fn ws_onmessage_js(socket: Websocket, callback: fn(String) -> Nil) -> Nil

@external(javascript, "./ffi.js", "ws_onopen_js")
pub fn ws_onopen_js(socket: Websocket, callback: fn() -> Nil) -> Nil

@external(javascript, "./ffi.js", "ws_onclose_js")
pub fn ws_onclose_js(socket: Websocket, callback: fn() -> Nil) -> Nil

@external(javascript, "./ffi.js", "ws_send_move_js")
pub fn ws_send_move_js(socket: Websocket, message: ApplyMoveMessage) -> Nil

@external(javascript, "./ffi.js", "ws_send_game_data_request_js")
pub fn ws_send_game_data_request_js(
  socket: Websocket,
  message: RequestGameDataMessage,
) -> Nil

@external(javascript, "./ffi.js", "ws_request_game_with_computer_js")
pub fn ws_request_game_with_computer_js(socket: Websocket, color: String) -> Nil

@external(javascript, "./ffi.js", "ws_init_js")
pub fn ws_init_js() -> Websocket

@external(javascript, "./ffi.js", "get_data_as_string_js")
pub fn get_data_as_string_js(object: String) -> String

@external(javascript, "./ffi.js", "get_data_field_js")
pub fn get_data_field_js(object: String, field: String) -> String

@external(javascript, "./ffi.js", "get_data_field_object_as_array_js")
pub fn get_data_field_object_as_array_js(
  object: String,
  field: String,
) -> Array(Array(String))

@external(javascript, "./ffi.js", "set_navigation_button_callback_js")
pub fn set_navigation_button_callback_js(callback: fn(String) -> Nil) -> Nil

@external(javascript, "./ffi.js", "url_pathname_js")
pub fn url_pathname_js() -> String

@external(javascript, "./ffi.js", "set_pathname_js")
pub fn set_pathname_js(pathname: String) -> Nil

@external(javascript, "./ffi.js", "get_color_select_value_js")
pub fn get_color_select_value_js() -> String

pub fn main() {
  let socket = ws_init_js()
  let app = application(init, update, view)
  let url_pathname = url_pathname_js()

  let assert Ok(interface) = lustre.start(app, "[gchessboard-lustre-app]", Nil)

  let ui_mode = case url_pathname {
    "/game/" <> game_id -> {
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
  let ui_app = application(ui_init(_, ui_mode, interface), ui_update, ui_view)
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
      orientation: None,
    )

  interface(dispatch(Set(config)))

  let on_computer_game_request_click = fn(color) {
    ws_request_game_with_computer_js(socket, color)
  }

  ui_interface(
    dispatch(SetOnComputerGameRequestClick(on_computer_game_request_click)),
  )

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
        interface(dispatch(ShowBoard))
        Nil
      }
      "{\"type\":\"request_game_data_response\"" <> _ -> {
        let moves_array = get_data_field_object_as_array_js(message, "moves")
        let fen = get_data_field_js(message, "fen")
        let user_color = case get_data_field_js(message, "user_color") {
          "white" -> {
            Some(WhiteOriented)
          }
          "black" -> {
            Some(BlackOriented)
          }
          _ -> {
            None
          }
        }
        let turn = case get_data_field_js(message, "turn") {
          "white" -> {
            White
          }
          "black" -> {
            Black
          }
          _ -> {
            panic as "Invalid turn"
          }
        }
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
        let player = case user_color {
          Some(WhiteOriented) -> {
            White
          }
          Some(BlackOriented) -> {
            types.Black
          }
          _ -> {
            types.Both
          }
        }
        let config =
          Config(
            moveable: Some(Moveable(
              player: Some(player),
              promotions: Some(promo_moves),
              fen: Some(fen),
              after: None,
              moves: Some(moves),
            )),
            orientation: user_color,
          )
        interface(dispatch(Set(config)))
        interface(dispatch(SetTurn(turn)))
        interface(dispatch(ShowBoard))
        Nil
      }
      "{\"type\":\"request_game_data\",\"error\":\"dne\"}" -> {
        set_pathname_js("/")
        ui_interface(dispatch(ChangeMode(LobbyMode)))
        interface(dispatch(HideBoard))
      }
      "{\"type\":\"request_game_with_computer_confirm\"" <> _
      | "{\"type\":\"request_game_with_computer_existing\"" <> _ -> {
        let moves = get_data_field_object_as_array_js(message, "moves")
        let fen = get_data_field_js(message, "fen")
        let turn = case get_data_field_js(message, "turn") {
          "white" -> {
            White
          }
          "black" -> {
            Black
          }
          _ -> {
            panic as "Invalid turn"
          }
        }
        let user_color = case get_data_field_js(message, "user_color") {
          "white" -> {
            Some(WhiteOriented)
          }
          "black" -> {
            Some(BlackOriented)
          }
          _ -> {
            None
          }
        }
        let game_id = get_data_field_js(message, "game_id")
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

        set_pathname_js("/game/" <> game_id)
        ui_interface(dispatch(ChangeMode(GameMode)))
        let player = case user_color {
          Some(WhiteOriented) -> {
            White
          }
          Some(BlackOriented) -> {
            types.Black
          }
          _ -> {
            types.Both
          }
        }
        let config =
          Config(
            moveable: Some(Moveable(
              player: Some(player),
              promotions: Some(promo_moves),
              fen: Some(fen),
              after: None,
              moves: Some(moves),
            )),
            orientation: user_color,
          )
        interface(dispatch(Set(config)))
        interface(dispatch(SetTurn(turn)))
        interface(dispatch(ShowBoard))
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

  let on_back_button_click = fn(pathname) {
    case pathname {
      "/" -> {
        ui_interface(dispatch(ChangeMode(LobbyMode)))
        interface(dispatch(HideBoard))
      }
      "/game/" <> _game_id -> {
        ui_interface(dispatch(ChangeMode(GameMode)))
        interface(dispatch(ShowBoard))
      }
      _ -> set_pathname_js("/")
    }
  }

  set_navigation_button_callback_js(on_back_button_click)

  Nil
}

pub fn ui_init(
  _,
  ui_mode: UiMode,
  chessboard_interface: fn(Action(Msg, ClientSpa)) -> Nil,
) {
  let game_mode_settings =
    GameModeSettings(
      promotion: False,
      promotion_on_click: None,
      from: None,
      to: None,
    )
  let lobby_mode_settings = LobbyModeSettings(None, False)
  #(
    UiState(
      ui_mode,
      lobby_mode_settings,
      game_mode_settings,
      chessboard_interface,
    ),
    effect.none(),
  )
}

pub fn ui_update(state: UiState, msg) {
  case msg {
    ChangeMode(mode) -> {
      #(
        UiState(
          mode: mode,
          lobby_mode_settings: state.lobby_mode_settings,
          game_mode_settings: state.game_mode_settings,
          chessboard_interface: state.chessboard_interface,
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
              chessboard_interface: state.chessboard_interface,
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
              chessboard_interface: state.chessboard_interface,
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
          chessboard_interface: state.chessboard_interface,
        ),
        effect.none(),
      )
    }
    ShowRequestGameWithComputerPrompt -> {
      case state.mode {
        LobbyMode -> {
          let new_state =
            UiState(
              mode: state.mode,
              lobby_mode_settings: LobbyModeSettings(
                on_computer_game_request_click: state.lobby_mode_settings.on_computer_game_request_click,
                computer_game_request_prompt_visibility: True,
              ),
              game_mode_settings: state.game_mode_settings,
              chessboard_interface: state.chessboard_interface,
            )
          #(new_state, effect.none())
        }
        _ -> {
          #(state, effect.none())
        }
      }
    }
    RequestGameWithComputer(color) -> {
      case state.mode {
        LobbyMode -> {
          // New game request logic
          let assert Some(on_computer_game_request_click) =
            state.lobby_mode_settings.on_computer_game_request_click
          on_computer_game_request_click(color)
          #(state, effect.none())
        }
        _ -> {
          #(state, effect.none())
        }
      }
    }
    SetOnComputerGameRequestClick(on_computer_game_request_click) -> {
      #(
        UiState(
          mode: state.mode,
          lobby_mode_settings: LobbyModeSettings(
            on_computer_game_request_click: Some(on_computer_game_request_click),
            computer_game_request_prompt_visibility: state.lobby_mode_settings.computer_game_request_prompt_visibility,
          ),
          game_mode_settings: state.game_mode_settings,
          chessboard_interface: state.chessboard_interface,
        ),
        effect.none(),
      )
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
            html.button(
              [
                id("title-button"),
                title_button_style(),
                event.on("click", fn(_) {
                  state.chessboard_interface(dispatch(HideBoard))
                  Ok(ChangeMode(LobbyMode))
                }),
              ],
              [text("shahmat.org")],
            ),
            html.br([]),
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
          div([], [
            html.button(
              [
                id("title-button"),
                title_button_style(),
                event.on("click", fn(_) {
                  state.chessboard_interface(dispatch(HideBoard))
                  set_pathname_js("/")
                  Ok(ChangeMode(LobbyMode))
                }),
              ],
              [text("shahmat.org")],
            ),
          ])
        }
      }
    }
    LobbyMode -> {
      div([], [
        html.button(
          [
            id("title-button"),
            title_button_style(),
            event.on("click", fn(_) {
              state.chessboard_interface(dispatch(HideBoard))
              set_pathname_js("/")
              Ok(ChangeMode(LobbyMode))
            }),
          ],
          [text("shahmat.org")],
        ),
        html.br([]),
        case state.lobby_mode_settings.computer_game_request_prompt_visibility {
          False -> {
            html.button(
              [
                event.on("click", fn(_) {
                  Ok(ShowRequestGameWithComputerPrompt)
                }),
              ],
              [text("PLAY WITH THE COMPUTER")],
            )
          }
          True -> {
            html.div([], [
              html.label(
                [
                  attribute.for("color-select"),
                  attribute.style([#("color", "#bababa")]),
                ],
                [text("Color:")],
              ),
              html.select([attribute.id("color-select")], [
                html.option([attribute.value("white")], "White"),
                html.option([attribute.value("black")], "Black"),
              ]),
              html.br([]),
              html.button(
                [
                  event.on("click", fn(_) {
                    Ok(RequestGameWithComputer(get_color_select_value_js()))
                  }),
                ],
                [text("Ready")],
              ),
            ])
          }
        },
      ])
    }
  }
}

pub fn title_button_style() {
  attribute.style([
    #("background", "none"),
    #("border", "none"),
    #("margin", "0"),
    #("padding", "0"),
    #("cursor", "pointer"),
    #("font-size", "30px"),
    #("color", "#bababa"),
  ])
}
