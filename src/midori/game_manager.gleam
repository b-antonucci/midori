import game_server.{type Message, new_game_from_fen, shutdown}
import gleam/dict.{type Dict}
import gleam/dynamic.{list}
import gleam/erlang/process.{type Subject}
import gleam/list
import gleam/option.{None, Some}
import gleam/otp/actor
import ids/uuid
import midori/bot_server_message.{type BotServerMessage, RequestBotMove}
import midori/client_ws_message.{
  type ClientFormatMoveList, BotMove, ClientFormatMoveList,
  update_game_message_to_json,
}
import midori/game_manager_message.{
  type GameInfo, type GameManagerMessage, ApplyAiMove, ApplyMove, ConfirmMove,
  GameInfo, GetGameInfo, NewGame, RemoveGame, Shutdown,
}
import midori/ws_server_message.{type WebsocketServerMessage, Send}
import move.{Normal}
import piece.{Bishop, Knight, Queen, Rook}
import position

pub type GameManagerState {
  GameManagerState(
    game_map: Dict(String, Subject(Message)),
    bot_server_pid: Subject(BotServerMessage),
    ws_server_subject: Subject(WebsocketServerMessage),
  )
}

fn handle_message(
  message: GameManagerMessage,
  state: GameManagerState,
) -> actor.Next(GameManagerMessage, GameManagerState) {
  case message {
    Shutdown -> actor.Stop(process.Normal)
    ApplyMove(client, game_id, user_id, move) -> {
      let server_result = dict.get(state.game_map, game_id)
      case server_result {
        Ok(server) -> {
          case game_server.apply_move_uci_string(server, move) {
            Ok(_) -> {
              let legal_moves = game_server.all_legal_moves(server)
              let length = list.length(legal_moves)
              case length {
                0 -> {
                  let response = ConfirmMove(move)
                  process.send(client, Ok(response))
                  actor.continue(state)
                }
                _ -> {
                  let fen = game_server.get_fen(server)

                  process.send(
                    state.bot_server_pid,
                    RequestBotMove(gameid: game_id, user_id: user_id, fen: fen),
                  )

                  let response = ConfirmMove(move)
                  process.send(client, Ok(response))
                  actor.continue(state)
                }
              }
            }
            Error(_) -> {
              process.send(client, Error("Invalid move"))
              actor.continue(state)
            }
          }
        }
        Error(_) -> {
          process.send(client, Error("Game not found"))
          actor.continue(state)
        }
      }
    }
    ApplyAiMove(game_id, user_id, move) -> {
      let assert Ok(server) = dict.get(state.game_map, game_id)
      let assert Ok(_) = game_server.apply_move_uci_string(server, move)
      let fen = game_server.get_fen(server)
      // TODO: There should be a function called all_legal_moves_aggregated or something
      // that gives us the moves in the correct format instead of all this work we do here.
      // We are duplicating work by processing the moves twice.
      let unformatted_moves = game_server.all_legal_moves(server)
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
            case list.find(acc.moves, fn(move) { move.0 == origin_string }) {
              Error(_) -> {
                let new_move = #(origin_string, [
                  position.to_string(move.to) <> promo,
                ])
                ClientFormatMoveList(moves: [new_move, ..acc.moves])
              }
              Ok(#(_, destinations)) -> {
                let new_destinations =
                  list.append(destinations, [
                    position.to_string(move.to) <> promo,
                  ])
                let new_move = #(origin_string, new_destinations)
                let new_moves =
                  list.filter(acc.moves, fn(move) { move.0 != origin_string })
                ClientFormatMoveList(moves: [new_move, ..new_moves])
              }
            }
          },
        )

      let ws_json_message =
        update_game_message_to_json(BotMove(moves: formatted_moves, fen: fen))

      process.send(state.ws_server_subject, Send(user_id, ws_json_message))

      actor.continue(state)
    }
    NewGame(client) -> {
      let server = game_server.new_server()
      case server {
        Ok(server) -> {
          case
            new_game_from_fen(
              server,
              "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
            )
          {
            Ok(_) -> {
              let game_id_result = uuid.generate_v7()
              case game_id_result {
                Ok(game_id) -> {
                  let game_map = dict.insert(state.game_map, game_id, server)
                  process.send(client, game_id_result)
                  actor.continue(GameManagerState(
                    game_map,
                    state.bot_server_pid,
                    state.ws_server_subject,
                  ))
                }
                Error(_) -> {
                  shutdown(server)
                  process.send(client, Error("Failed to generate game id"))
                  actor.continue(state)
                }
              }
            }
            Error(_) -> {
              shutdown(server)
              process.send(client, Error("Failed to create game"))
              actor.continue(state)
            }
          }
        }
        Error(_) -> {
          process.send(client, Error("Failed to create game"))
          actor.continue(state)
        }
      }
    }
    RemoveGame(client, id) -> {
      let assert Ok(server) = dict.get(state.game_map, id)
      shutdown(server)
      let game_map = dict.delete(state.game_map, id)
      process.send(client, Ok(Nil))
      actor.continue(GameManagerState(
        game_map,
        state.bot_server_pid,
        state.ws_server_subject,
      ))
    }
    GetGameInfo(client, id) -> {
      case dict.get(state.game_map, id) {
        Ok(server) -> {
          let fen = game_server.get_fen(server)
          let status_option = game_server.get_status(server)
          let moves = game_server.all_legal_moves(server)
          case status_option {
            Some(status) -> {
              process.send(
                client,
                Ok(GameInfo(fen: fen, status: status, moves: moves)),
              )
              actor.continue(state)
            }
            None -> {
              process.send(client, Error("Game not found"))
              actor.continue(state)
            }
          }
        }
        Error(_) -> {
          process.send(client, Error("Game not found"))
          actor.continue(state)
        }
      }
    }
  }
}

pub fn start_game_manager(
  bot_server_pid: Subject(BotServerMessage),
  ws_server_subject: Subject(WebsocketServerMessage),
) {
  let game_map = dict.new()
  let actor =
    actor.start(
      GameManagerState(game_map, bot_server_pid, ws_server_subject),
      handle_message,
    )
  actor
}
