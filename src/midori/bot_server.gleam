import game.{from_fen_string}
import gleam/erlang/process.{type Subject}
import gleam/int
import gleam/list
import gleam/option.{Some}
import gleam/otp/actor
import midori/bot_server_message.{
  type BotServerMessage, RequestBotMove, SetGameManagerSubject,
}
import midori/game_manager_message.{type GameManagerMessage, ApplyAiMove}

import move
import piece.{Bishop, King, Knight, Pawn, Queen, Rook}
import position

pub type GameId =
  String

pub type Fen =
  String

pub type BotServerState {
  BotServerState(
    game_server_subject: option.Option(Subject(GameManagerMessage)),
  )
}

fn handle_message(
  message: BotServerMessage,
  state: BotServerState,
) -> actor.Next(BotServerMessage, BotServerState) {
  let state = case message {
    RequestBotMove(game_id, user_id, fen) -> {
      let game_result = from_fen_string(fen)
      case game_result {
        Ok(game) -> {
          case game.all_legal_moves(game) {
            Ok(legal_moves) -> {
              let move_count = list.length(legal_moves)
              let random_move_index = int.random(move_count)
              let maybe_random_move =
                list.drop(legal_moves, random_move_index) |> list.first
              case maybe_random_move {
                Ok(move) -> {
                  let promo = case move {
                    move.Normal(from: _, to: _, promotion: Some(piece)) -> {
                      case piece.kind {
                        Pawn -> ""
                        Bishop -> "b"
                        King -> ""
                        Rook -> "r"
                        Knight -> "n"
                        Queen -> "q"
                      }
                    }
                    _ -> ""
                  }
                  let assert Some(game_server_subject) =
                    state.game_server_subject
                  process.send(
                    game_server_subject,
                    ApplyAiMove(
                      game_id,
                      user_id,
                      position.to_string(move.from)
                        <> position.to_string(move.to)
                        <> promo,
                    ),
                  )
                }
                Error(_) -> Nil
              }
            }
            Error(_) -> Nil
          }
        }
        Error(_) -> Nil
      }
      state
    }
    SetGameManagerSubject(game_server_subject) -> {
      let state = BotServerState(option.Some(game_server_subject))
      state
    }
  }
  actor.continue(state)
}

pub fn start_bot_server(
  subject: Subject(Subject(BotServerMessage)),
) -> Result(Subject(BotServerMessage), _) {
  let assert Ok(actor) =
    actor.start(BotServerState(option.None), handle_message)
  process.send(subject, actor)

  Ok(actor)
}
