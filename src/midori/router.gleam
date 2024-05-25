import gleam/erlang/process
import gleam/json.{array, object, string as json_string}
import gleam/list
import gleam/option.{None, Some}
import gleam/string_builder
import midori/client_ws_message.{type ClientFormatMoveList, ClientFormatMoveList}
import midori/game_manager_message.{GetGameInfo, NewGame, RemoveGame}
import midori/user_manager_message.{
  AddGameToUser, AddUser, ConfirmUserExists, GetUserGame,
}
import midori/web.{type Context}
import move.{Normal}
import piece.{Bishop, Knight, Queen, Rook}
import position
import status
import wisp.{type Request, type Response}

const html = "
<!DOCTYPE html>
<html lang=\"en\">

<head>
    <meta charset=\"UTF-8\" />
    <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\" />
    <title>gchessboard</title>

    <style>
        body {
            background-color: #151411;
        }
    </style>

    <script type=\"module\" src=\"/static/index.js\"></script>
</head>

<body>
    <div ui-lustre-app></div>
    <div id=\"no-context-menu-wrapper\"><div gchessboard-lustre-app></div></div>
</body>

</html>
"

pub fn handle_request(req: Request, ctx: Context) -> Response {
  use req <- web.middleware(req, ctx)
  case wisp.path_segments(req) {
    ["request_game_with_computer"] -> {
      // TODO: need to clean this up using result and error handling functions
      case wisp.get_cookie(req, "user_id", wisp.PlainText) {
        Ok(user_id) -> {
          let get_user_game_result =
            process.call(
              ctx.user_manager_subject,
              GetUserGame(_, user_id),
              1000,
            )
          case get_user_game_result {
            Ok(Some(game_id)) -> {
              let get_game_info_result =
                process.call(
                  ctx.game_manager_subject,
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
                      wisp.json_response(
                        json.to_string_builder(
                          json.object([
                            #("game_id", json.string(game_id)),
                            #("fen", json.string(game_info.fen)),
                            #("moves", object(moves_with_json_dests)),
                          ]),
                        ),
                        200,
                      )
                    }
                    _ -> {
                      case
                        process.call(
                          ctx.game_manager_subject,
                          RemoveGame(_, game_id),
                          1000,
                        )
                      {
                        Ok(_) -> {
                          case
                            process.call(
                              ctx.game_manager_subject,
                              NewGame,
                              1000,
                            )
                          {
                            Ok(new_game_id) -> {
                              case
                                process.call(
                                  ctx.user_manager_subject,
                                  AddGameToUser(_, user_id, new_game_id),
                                  1000,
                                )
                              {
                                Ok(_) -> {
                                  let get_game_info_result =
                                    process.call(
                                      ctx.game_manager_subject,
                                      GetGameInfo(_, new_game_id),
                                      1000,
                                    )
                                  case get_game_info_result {
                                    Ok(game_info) -> {
                                      let moves = format_move(game_info.moves)
                                      let moves = moves.moves
                                      let moves_with_json_dests =
                                        list.map(moves, fn(move) {
                                          #(
                                            move.0,
                                            array(move.1, of: json_string),
                                          )
                                        })
                                      wisp.json_response(
                                        json.to_string_builder(
                                          json.object([
                                            #(
                                              "game_id",
                                              json.string(new_game_id),
                                            ),
                                            #("fen", json.string(game_info.fen)),
                                            #(
                                              "moves",
                                              object(moves_with_json_dests),
                                            ),
                                          ]),
                                        ),
                                        200,
                                      )
                                    }
                                    Error(_msg) -> {
                                      wisp.html_response(
                                        string_builder.from_string("Error"),
                                        500,
                                      )
                                    }
                                  }
                                }
                                Error(_msg) -> {
                                  wisp.html_response(
                                    string_builder.from_string("Error"),
                                    500,
                                  )
                                }
                              }
                            }
                            Error(_msg) -> {
                              wisp.html_response(
                                string_builder.from_string("Error"),
                                500,
                              )
                            }
                          }
                        }
                        Error(_msg) -> {
                          wisp.html_response(
                            string_builder.from_string("Error"),
                            500,
                          )
                        }
                      }
                    }
                  }
                }
                Error(_msg) -> {
                  wisp.html_response(string_builder.from_string("Error"), 500)
                }
              }
            }
            Ok(None) -> {
              case process.call(ctx.game_manager_subject, NewGame, 1000) {
                Ok(game_id) -> {
                  case
                    process.call(
                      ctx.user_manager_subject,
                      AddGameToUser(_, user_id, game_id),
                      1000,
                    )
                  {
                    Ok(_) -> {
                      let get_game_info_result =
                        process.call(
                          ctx.game_manager_subject,
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
                          wisp.json_response(
                            json.to_string_builder(
                              json.object([
                                #("game_id", json.string(game_id)),
                                #("fen", json.string(fen)),
                                #("moves", object(moves_with_json_dests)),
                              ]),
                            ),
                            200,
                          )
                        }
                        Error(_msg) -> {
                          wisp.html_response(
                            string_builder.from_string("Error"),
                            500,
                          )
                        }
                      }
                    }
                    Error(_msg) -> {
                      wisp.html_response(
                        string_builder.from_string("Error"),
                        500,
                      )
                    }
                  }
                }
                Error(_msg) -> {
                  wisp.html_response(string_builder.from_string("Error"), 500)
                }
              }
            }
            Error(_msg) -> {
              wisp.html_response(string_builder.from_string("Error"), 500)
            }
          }
        }
        Error(_msg) -> {
          wisp.html_response(string_builder.from_string("Error"), 500)
        }
      }
    }
    ["game", _game_id] -> {
      case wisp.get_cookie(req, "user_id", wisp.PlainText) {
        Ok(user_id) -> {
          let user_check_result =
            process.call(
              ctx.user_manager_subject,
              ConfirmUserExists(_, user_id),
              1000,
            )
          case user_check_result {
            Ok(_) -> {
              let game_check_result =
                process.call(
                  ctx.user_manager_subject,
                  GetUserGame(_, user_id),
                  1000,
                )
              case game_check_result {
                Ok(Some(_game_id)) -> {
                  wisp.html_response(string_builder.from_string(html), 200)
                }
                _ -> {
                  wisp.redirect("/")
                }
              }
            }
            Error(_msg) -> {
              wisp.redirect("/")
            }
          }
        }
        Error(_msg) -> {
          wisp.redirect("/")
        }
      }
    }
    _ -> {
      case wisp.get_cookie(req, "user_id", wisp.PlainText) {
        Ok(user_id) -> {
          let user_check_result =
            process.call(
              ctx.user_manager_subject,
              ConfirmUserExists(_, user_id),
              1000,
            )

          case user_check_result {
            Ok(_) -> {
              wisp.html_response(string_builder.from_string(html), 200)
            }
            Error(_msg) -> {
              case process.call(ctx.user_manager_subject, AddUser, 1000) {
                Ok(user_id) -> {
                  wisp.html_response(string_builder.from_string(html), 200)
                  |> wisp.set_cookie(
                    req,
                    "user_id",
                    user_id,
                    wisp.PlainText,
                    60 * 60 * 24,
                  )
                }
                Error(_msg) -> {
                  wisp.html_response(string_builder.from_string("Error"), 500)
                }
              }
            }
          }
        }
        Error(_msg) -> {
          case process.call(ctx.user_manager_subject, AddUser, 1000) {
            Ok(user_id) -> {
              wisp.html_response(string_builder.from_string(html), 200)
              |> wisp.set_cookie(
                req,
                "user_id",
                user_id,
                wisp.PlainText,
                60 * 60 * 24,
              )
            }
            Error(_msg) -> {
              wisp.html_response(string_builder.from_string("Error"), 500)
            }
          }
        }
      }
    }
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
