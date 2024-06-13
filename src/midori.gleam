import gleam/bit_array.{base64_decode}
import gleam/bytes_builder
import gleam/dict
import gleam/dynamic.{field, string}
import gleam/erlang/process.{type Subject}
import gleam/http/request.{type Request, Request, get_cookies}
import gleam/http/response.{type Response}
import gleam/json.{array, object, string as json_string}
import gleam/list
import gleam/option.{None, Some}
import gleam/otp/actor
import gleam/otp/supervisor
import gleam/result
import midori/bot_server
import midori/bot_server_message.{SetGameManagerSubject}
import midori/client_ws_message.{
  type ClientFormatMoveList, ClientFormatMoveList, ConfirmMove, RequestGameData,
  update_game_message_to_json,
}
import midori/game_manager
import midori/game_manager_message.{
  type GameManagerMessage, ApplyMove, GetGameInfo, NewGame, RemoveGame,
}
import midori/ping_server.{type PingServerMessage}
import midori/router
import midori/uci_move.{convert_move}
import midori/user_manager
import midori/user_manager_message.{
  type UserManagerMessage, AddGameToUser, GetUserGame,
}
import midori/web.{Context}
import midori/ws_server
import midori/ws_server_message.{
  type WebsocketServerMessage, AddConnection, CheckForExistingConnection,
  RemoveConnection,
}
import mist.{type Connection, type ResponseData}
import move.{Normal}
import piece.{Bishop, Knight, Queen, Rook}
import position
import status
import wisp

type ConnectionState {
  ConnectionState(
    id: String,
    ping_server_subject: Subject(PingServerMessage),
    game_manager_subject: Subject(GameManagerMessage),
    ws_server_subject: Subject(WebsocketServerMessage),
    user_manager_subject: Subject(UserManagerMessage),
  )
  ConnectionErrorState
}

type ApplyMoveMessage {
  ApplyMoveMessage(move: String)
}

pub type RequestGameDataMessage {
  RequestGameDataMessage(game_id: String)
}

type RequestGameWithComputerMessage {
  RequestGameWithComputerMessage(color: String)
}

pub fn main() {
  let selector = process.new_selector()

  wisp.configure_logger()
  let secret_key_base = wisp.random_string(64)

  let subject = process.new_subject()

  let bot_server_child_spec =
    supervisor.worker(fn(_) { bot_server.start_bot_server(subject) })
  let children = fn(children) {
    children
    |> supervisor.add(bot_server_child_spec)
  }

  let assert Ok(_) = supervisor.start(children)
  let assert Ok(bot_server_subject) = process.receive(subject, 100)

  let assert Ok(ws_server_subject) = ws_server.start_ws_server()
  let assert Ok(ping_server_subject) = ping_server.start_ping_server()
  let assert Ok(user_manager_subject) = user_manager.start_user_manager()
  let assert Ok(game_manager_subject) =
    game_manager.start_game_manager(bot_server_subject, ws_server_subject)
  process.send(bot_server_subject, SetGameManagerSubject(game_manager_subject))

  // A context is constructed holding the static directory path.
  let ctx =
    Context(
      static_directory: static_directory(),
      game_manager_subject: game_manager_subject,
      user_manager_subject: user_manager_subject,
    )

  // The handle_request function is partially applied with the context to make
  // the request handler function that only takes a request.
  let handler = router.handle_request(_, ctx)

  let not_found =
    response.new(404)
    |> response.set_body(mist.Bytes(bytes_builder.new()))

  let assert Ok(_) =
    fn(req: Request(Connection)) -> Response(ResponseData) {
      case request.path_segments(req) {
        ["ws"] ->
          mist.websocket(
            request: req,
            on_init: fn(websocket) {
              case mist.read_body(req, 1000) {
                Ok(req_body) -> {
                  let encoded_user_id =
                    dict.get(dict.from_list(get_cookies(req_body)), "user_id")
                  let user_id_result =
                    result.map(encoded_user_id, base64_decode)
                    |> result.flatten
                    |> result.map(bit_array.to_string)
                    |> result.flatten
                  case user_id_result {
                    Ok(user_id) -> {
                      let conn_exists =
                        process.call(
                          ws_server_subject,
                          CheckForExistingConnection(_, user_id),
                          1000,
                        )
                      case conn_exists {
                        True -> {
                          #(ConnectionErrorState, Some(selector))
                        }
                        False -> {
                          let state =
                            ConnectionState(
                              user_id,
                              ping_server_subject,
                              game_manager_subject,
                              ws_server_subject,
                              user_manager_subject,
                            )
                          process.send(
                            ws_server_subject,
                            AddConnection(user_id, websocket),
                          )
                          #(state, Some(selector))
                        }
                      }
                    }
                    Error(_) -> {
                      #(ConnectionErrorState, Some(selector))
                    }
                  }
                }
                Error(_) -> {
                  #(ConnectionErrorState, Some(selector))
                }
              }
            },
            on_close: fn(state) {
              case state {
                ConnectionState(id, _, _, _, _) ->
                  process.send(ws_server_subject, RemoveConnection(id))
                ConnectionErrorState -> Nil
              }
              Nil
            },
            handler: handle_ws_message,
          )

        _ -> not_found
      }
    }
    |> mist.new
    |> mist.port(8000)
    |> mist.start_http

  let assert Ok(_) =
    wisp.mist_handler(handler, secret_key_base)
    |> mist.new
    |> mist.port(8001)
    |> mist.start_http

  process.sleep_forever()
}

pub fn static_directory() -> String {
  // The priv directory is where we store non-Gleam and non-Erlang files,
  // including static assets to be served.
  // This function returns an absolute path and works both in development and in
  // production after compilation.
  let assert Ok(priv_directory) = wisp.priv_directory("midori")
  priv_directory <> "/static"
}

pub type MyMessage {
  Broadcast(String)
}

fn handle_ws_message(state: ConnectionState, conn, message) {
  case state {
    ConnectionState(
      id,
      _ping_server_subject,
      game_manager_subject,
      _ws_server_subject,
      user_manager_subject,
    ) -> {
      case message {
        mist.Text("0") -> {
          // process.send(state.ping_server_subject, ping_server.Ping(conn))
          actor.continue(state)
        }
        mist.Text(ws_message) -> {
          case ws_message {
            "{\"type\":\"request_game_data\"" <> _ -> {
              let message_decoder =
                dynamic.decode1(
                  RequestGameDataMessage,
                  field("game_id", string),
                )
              case json.decode(ws_message, message_decoder) {
                Ok(RequestGameDataMessage(game_id)) -> {
                  let game_manager_response_result =
                    process.call(
                      game_manager_subject,
                      GetGameInfo(_, game_id),
                      1000,
                    )
                  case game_manager_response_result {
                    Ok(game_manager_response) -> {
                      let unformatted_moves = game_manager_response.moves
                      let formatted_moves =
                        list.fold(
                          unformatted_moves,
                          ClientFormatMoveList(moves: []),
                          fn(acc, move) {
                            let origin = move.from
                            let origin_string = position.to_string(origin)
                            let promo = case move {
                              Normal(_, _, Some(promo)) ->
                                case promo.kind {
                                  Queen -> "q"
                                  Rook -> "r"
                                  Knight -> "n"
                                  Bishop -> "b"
                                  _ -> ""
                                }
                              _ -> ""
                            }
                            case
                              list.find(acc.moves, fn(move) {
                                move.0 == origin_string
                              })
                            {
                              Error(_) -> {
                                let new_move = #(origin_string, [
                                  position.to_string(move.to) <> promo,
                                ])
                                ClientFormatMoveList(moves: [
                                  new_move,
                                  ..acc.moves
                                ])
                              }
                              Ok(#(_, destinations)) -> {
                                let new_destinations =
                                  list.append(destinations, [
                                    position.to_string(move.to) <> promo,
                                  ])
                                let new_move = #(
                                  origin_string,
                                  new_destinations,
                                )
                                let new_moves =
                                  list.filter(acc.moves, fn(move) {
                                    move.0 != origin_string
                                  })
                                ClientFormatMoveList(moves: [
                                  new_move,
                                  ..new_moves
                                ])
                              }
                            }
                          },
                        )

                      let game_data_message =
                        RequestGameData(
                          moves: formatted_moves,
                          fen: game_manager_response.fen,
                        )
                      let json = update_game_message_to_json(game_data_message)

                      case mist.send_text_frame(conn, json) {
                        Ok(_) -> actor.continue(state)
                        Error(_) -> actor.continue(state)
                      }
                      actor.continue(state)
                    }
                    Error(_) -> {
                      case
                        mist.send_text_frame(
                          conn,
                          "{\"type\":\"request_game_data\",\"error\":\"dne\"}",
                        )
                      {
                        Ok(_) -> actor.continue(state)
                        Error(_) -> actor.continue(state)
                      }
                    }
                  }
                }
                Error(_) -> {
                  actor.continue(state)
                }
              }
            }
            "{\"type\":\"move\"" <> _ -> {
              let message_decoder =
                dynamic.decode1(ApplyMoveMessage, field("move", string))
              case json.decode(ws_message, message_decoder) {
                Ok(ApplyMoveMessage(move)) -> {
                  let some_game_id_result =
                    process.call(user_manager_subject, GetUserGame(_, id), 1000)
                  let uci_move_result = convert_move(move)
                  case some_game_id_result, uci_move_result {
                    Ok(Some(game_id)), Ok(uci_move) -> {
                      let game_manager_response_result =
                        process.call(
                          game_manager_subject,
                          ApplyMove(_, game_id, id, uci_move),
                          1000,
                        )

                      case game_manager_response_result {
                        Ok(game_manager_response) -> {
                          let update_game_message =
                            ConfirmMove(move: game_manager_response.move)
                          let json =
                            update_game_message_to_json(update_game_message)

                          case mist.send_text_frame(conn, json) {
                            Ok(_) -> actor.continue(state)
                            Error(_) -> actor.continue(state)
                          }
                        }
                        Error(_) -> actor.continue(state)
                      }
                    }
                    _, _ -> actor.continue(state)
                  }
                }
                Error(_) -> {
                  actor.continue(state)
                }
              }
            }
            "{\"type\":\"request_game_with_computer\"" <> _ -> {
              let get_user_game_result =
                process.call(user_manager_subject, GetUserGame(_, id), 1000)
              case get_user_game_result {
                Ok(Some(game_id)) -> {
                  let get_game_info_result =
                    process.call(
                      game_manager_subject,
                      GetGameInfo(_, game_id),
                      1000,
                    )
                  case get_game_info_result {
                    Ok(game_info) -> {
                      case game_info.status {
                        status.InProgress(_, _) -> {
                          let moves = format_move(game_info.moves)
                          let moves = moves.moves
                          let moves_with_json_dests =
                            list.map(moves, fn(move) {
                              #(move.0, array(move.1, of: json_string))
                            })

                          let json =
                            json.to_string(
                              json.object([
                                #("game_id", json.string(game_id)),
                                #("fen", json.string(game_info.fen)),
                                #("moves", object(moves_with_json_dests)),
                              ]),
                            )
                          case mist.send_text_frame(conn, json) {
                            Ok(_) -> actor.continue(state)
                            Error(_) -> actor.continue(state)
                          }
                          actor.continue(state)
                        }
                        _ -> {
                          case
                            process.call(
                              game_manager_subject,
                              RemoveGame(_, game_id),
                              1000,
                            )
                          {
                            Ok(_) -> {
                              case
                                process.call(
                                  game_manager_subject,
                                  NewGame,
                                  1000,
                                )
                              {
                                Ok(new_game_id) -> {
                                  case
                                    process.call(
                                      user_manager_subject,
                                      AddGameToUser(_, id, new_game_id),
                                      1000,
                                    )
                                  {
                                    Ok(_) -> {
                                      let get_game_info_result =
                                        process.call(
                                          game_manager_subject,
                                          GetGameInfo(_, new_game_id),
                                          1000,
                                        )
                                      case get_game_info_result {
                                        Ok(game_info) -> {
                                          let moves =
                                            format_move(game_info.moves)
                                          let moves = moves.moves
                                          let moves_with_json_dests =
                                            list.map(moves, fn(move) {
                                              #(
                                                move.0,
                                                array(move.1, of: json_string),
                                              )
                                            })
                                          let json =
                                            json.to_string(
                                              json.object([
                                                #(
                                                  "game_id",
                                                  json.string(new_game_id),
                                                ),
                                                #(
                                                  "fen",
                                                  json.string(game_info.fen),
                                                ),
                                                #(
                                                  "moves",
                                                  object(moves_with_json_dests),
                                                ),
                                              ]),
                                            )
                                          case
                                            mist.send_text_frame(conn, json)
                                          {
                                            Ok(_) -> actor.continue(state)
                                            Error(_) -> actor.continue(state)
                                          }
                                          actor.continue(state)
                                        }
                                        Error(_msg) -> {
                                          actor.continue(state)
                                        }
                                      }
                                    }
                                    Error(_msg) -> {
                                      actor.continue(state)
                                    }
                                  }
                                }
                                Error(_msg) -> {
                                  actor.continue(state)
                                }
                              }
                            }
                            Error(_msg) -> {
                              actor.continue(state)
                            }
                          }
                        }
                      }
                    }
                    Error(_msg) -> {
                      actor.continue(state)
                    }
                  }
                }
                Ok(None) -> {
                  let message_decoder =
                    dynamic.decode1(
                      RequestGameWithComputerMessage,
                      field("color", string),
                    )
                  case json.decode(ws_message, message_decoder) {
                    Ok(RequestGameWithComputerMessage(_color)) -> {
                      case process.call(game_manager_subject, NewGame, 1000) {
                        Ok(game_id) -> {
                          case
                            process.call(
                              user_manager_subject,
                              AddGameToUser(_, id, game_id),
                              1000,
                            )
                          {
                            Ok(_) -> {
                              let get_game_info_result =
                                process.call(
                                  game_manager_subject,
                                  GetGameInfo(_, game_id),
                                  1000,
                                )
                              case get_game_info_result {
                                Ok(game_info) -> {
                                  let fen = game_info.fen
                                  let moves = format_move(game_info.moves)
                                  let moves = moves.moves
                                  let moves_with_json_dests =
                                    list.map(moves, fn(move) {
                                      #(move.0, array(move.1, of: json_string))
                                    })
                                  let json =
                                    json.to_string(
                                      json.object([
                                        #("game_id", json.string(game_id)),
                                        #("fen", json.string(fen)),
                                        #(
                                          "moves",
                                          object(moves_with_json_dests),
                                        ),
                                      ]),
                                    )
                                  case mist.send_text_frame(conn, json) {
                                    Ok(_) -> actor.continue(state)
                                    Error(_) -> actor.continue(state)
                                  }
                                  actor.continue(state)
                                }
                                Error(_msg) -> {
                                  actor.continue(state)
                                }
                              }
                            }
                            Error(_msg) -> {
                              actor.continue(state)
                            }
                          }
                        }
                        Error(_msg) -> {
                          actor.continue(state)
                        }
                      }
                    }
                    Error(_) -> {
                      actor.continue(state)
                    }
                  }
                }
                Error(_msg) -> {
                  actor.continue(state)
                }
              }
            }
            _ -> actor.continue(state)
          }
        }
        mist.Text(_) | mist.Binary(_) -> {
          actor.continue(state)
        }
        mist.Custom(Broadcast(_text)) -> {
          actor.continue(state)
        }
        mist.Closed | mist.Shutdown -> actor.Stop(process.Normal)
      }
    }
    ConnectionErrorState -> actor.continue(state)
  }
}

pub fn format_move(moves: List(move.Move)) -> ClientFormatMoveList {
  let formatted_moves =
    list.fold(moves, ClientFormatMoveList(moves: []), fn(acc, move) {
      let origin = move.from
      let origin_string = position.to_string(origin)
      let promo = case move {
        Normal(_, _, Some(promo)) ->
          case promo.kind {
            Queen -> "q"
            Rook -> "r"
            Knight -> "n"
            Bishop -> "b"
            _ -> ""
          }
        _ -> ""
      }
      case list.find(acc.moves, fn(move) { move.0 == origin_string }) {
        Error(_) -> {
          let new_move = #(origin_string, [position.to_string(move.to) <> promo])
          ClientFormatMoveList(moves: [new_move, ..acc.moves])
        }
        Ok(#(_, destinations)) -> {
          let new_destinations =
            list.append(destinations, [position.to_string(move.to) <> promo])
          let new_move = #(origin_string, new_destinations)
          let new_moves =
            list.filter(acc.moves, fn(move) { move.0 != origin_string })
          ClientFormatMoveList(moves: [new_move, ..new_moves])
        }
      }
    })
  formatted_moves
}
