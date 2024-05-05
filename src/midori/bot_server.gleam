import gleam/erlang/process.{type Subject}
import gleam/list
import gleam/option
import gleam/otp/actor
import gleam/queue
import gleam/string
import glexec.{type Pids, Execve, run_async}
import midori/bot_server_message.{
  type BotServerMessage, NextMove, RequestBotMove, SendBotMove,
  SetGameManagerSubject, SetOsPid, SetSelfSubject,
}
import midori/game_manager_message.{type GameManagerMessage, ApplyAiMove}
import midori/user_id.{type UserId}

pub type GameId =
  String

pub type Fen =
  String

pub type MoveRequestQueue =
  queue.Queue(#(GameId, UserId, Fen))

pub type BotServerState {
  BotServerState(
    self_subject: option.Option(Subject(BotServerMessage)),
    game_server_subject: option.Option(Subject(GameManagerMessage)),
    ospid: option.Option(Int),
    move_request_queue: MoveRequestQueue,
    current_request: option.Option(#(GameId, UserId, Fen)),
  )
}

fn handle_message(
  message: BotServerMessage,
  state: BotServerState,
) -> actor.Next(BotServerMessage, BotServerState) {
  let state = case message {
    NextMove -> {
      case state.current_request {
        option.None -> {
          case queue.pop_front(state.move_request_queue) {
            Error(_) -> state
            Ok(#(#(game_id, user_id, fen), new_move_request_queue)) -> {
              let assert option.Some(ospid) = state.ospid
              let assert Ok(_) =
                glexec.send(ospid, "position fen " <> fen <> "\n")
              let assert Ok(_) = glexec.send(ospid, "go depth 1\n")
              BotServerState(
                state.self_subject,
                state.game_server_subject,
                state.ospid,
                new_move_request_queue,
                option.Some(#(game_id, user_id, fen)),
              )
            }
          }
        }
        option.Some(#(_game_id, _user_id, fen)) -> {
          let assert option.Some(ospid) = state.ospid
          let assert Ok(_) = glexec.send(ospid, "position fen " <> fen <> "\n")
          let assert Ok(_) = glexec.send(ospid, "go depth 1\n")
          state
        }
      }
    }
    RequestBotMove(gameid, user_id, fen) -> {
      case
        queue.is_empty(state.move_request_queue)
        && state.current_request == option.None
      {
        True -> {
          let state =
            BotServerState(
              state.self_subject,
              state.game_server_subject,
              state.ospid,
              state.move_request_queue,
              option.Some(#(gameid, user_id, fen)),
            )
          let assert option.Some(ospid) = state.ospid
          let assert Ok(_) = glexec.send(ospid, "position fen " <> fen <> "\n")
          let assert Ok(_) = glexec.send(ospid, "go depth 1\n")
          state
        }
        False -> {
          let move_request_queue =
            queue.push_back(state.move_request_queue, #(gameid, user_id, fen))
          let state =
            BotServerState(
              state.self_subject,
              state.game_server_subject,
              state.ospid,
              move_request_queue,
              state.current_request,
            )
          state
        }
      }
    }
    SendBotMove(move) -> {
      let assert option.Some(#(game_id, user_id, _fen)) = state.current_request
      let assert option.Some(game_manager_subject) = state.game_server_subject
      process.send(game_manager_subject, ApplyAiMove(game_id, user_id, move))
      let state =
        BotServerState(
          state.self_subject,
          state.game_server_subject,
          state.ospid,
          state.move_request_queue,
          option.None,
        )
      let assert option.Some(self_subject) = state.self_subject
      process.send(self_subject, NextMove)
      state
    }
    SetSelfSubject(self_subject) -> {
      let state =
        BotServerState(
          option.Some(self_subject),
          state.game_server_subject,
          state.ospid,
          state.move_request_queue,
          state.current_request,
        )
      state
    }
    SetOsPid(ospid) -> {
      let state =
        BotServerState(
          state.self_subject,
          state.game_server_subject,
          option.Some(ospid),
          state.move_request_queue,
          state.current_request,
        )
      state
    }
    SetGameManagerSubject(game_server_subject) -> {
      let state =
        BotServerState(
          state.self_subject,
          option.Some(game_server_subject),
          state.ospid,
          state.move_request_queue,
          state.current_request,
        )
      state
    }
  }
  actor.continue(state)
}

pub fn start_bot_server(
  game_server_subject,
) -> Result(Subject(BotServerMessage), _) {
  let assert Ok(actor) =
    actor.start(
      BotServerState(
        option.None,
        game_server_subject,
        option.None,
        queue.from_list([]),
        option.None,
      ),
      handle_message,
    )

  let fairy_stockfish_command =
    Execve(["./fairy-stockfish-largeboard_x86-64-modern"])
  let options =
    glexec.new()
    |> glexec.with_stdin(glexec.StdinPipe)
    |> glexec.with_stdout(
      glexec.StdoutFun(fn(_atom, _int, string) {
        case string.split(string, "bestmove") {
          [_] -> Nil
          [_, move] -> {
            let assert Ok(move) =
              list.first(string.split(string.trim(move), " "))
            actor.send(actor, SendBotMove(move))
            Nil
          }
          [_, ..moves] -> {
            //multiple moves, we need to extract each move and send it to the game manager
            list.map(moves, fn(move) {
              let assert Ok(move) =
                list.first(string.split(string.trim(move), " "))
              actor.send(actor, SendBotMove(move))
            })
            Nil
          }
          _ -> Nil
        }
      }),
    )
  let assert Ok(glexec.Pids(_pid, ospid)) =
    run_async(options, fairy_stockfish_command)
  let assert Ok(_) = glexec.send(ospid, "setoption name Skill Level value 1\n")
  actor.send(actor, SetOsPid(ospid))
  actor.send(actor, SetSelfSubject(actor))
  Ok(actor)
}
