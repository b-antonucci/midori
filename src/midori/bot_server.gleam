import gleam/erlang/process.{type Subject}
import gleam/list
import gleam/option
import gleam/otp/actor
import gleam/queue
import gleam/string
import glexec.{type Pids, Execve, run_async}
import midori/bot_server_message.{
  type BotServerMessage, RequestBotMove, SendBotMove, SetGameManagerSubject,
  SetOsPid,
}
import midori/game_manager_message.{type GameManagerMessage, ApplyAiMove}

pub type MoveRequestQueue =
  queue.Queue(String)

pub type BotServerState {
  BotServerState(
    game_server_subject: option.Option(Subject(GameManagerMessage)),
    ospid: option.Option(Int),
    move_request_queue: MoveRequestQueue,
  )
}

fn handle_message(
  message: BotServerMessage,
  state: BotServerState,
) -> actor.Next(BotServerMessage, BotServerState) {
  let state = case message {
    RequestBotMove(gameid, fen) -> {
      let assert option.Some(ospid) = state.ospid
      let assert Ok(_) = glexec.send(ospid, "position fen " <> fen <> "\n")
      let assert Ok(_) = glexec.send(ospid, "go movetime 1\n")
      let move_request_queue = queue.push_back(state.move_request_queue, gameid)
      let state =
        BotServerState(
          state.game_server_subject,
          state.ospid,
          move_request_queue,
        )
      state
    }
    SendBotMove(move) -> {
      let assert Ok(#(game_id, _)) = queue.pop_front(state.move_request_queue)
      let assert option.Some(game_manager_subject) = state.game_server_subject
      process.send(game_manager_subject, ApplyAiMove(game_id, move))
      state
    }
    SetOsPid(ospid) -> {
      let state =
        BotServerState(
          state.game_server_subject,
          option.Some(ospid),
          state.move_request_queue,
        )
      state
    }
    SetGameManagerSubject(game_server_subject) -> {
      let state =
        BotServerState(
          option.Some(game_server_subject),
          state.ospid,
          state.move_request_queue,
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
      BotServerState(game_server_subject, option.None, queue.from_list([])),
      handle_message,
    )

  let assert fairy_stockfish_command =
    Execve(["./fairy-stockfish-largeboard_x86-64-modern"])
  let options =
    glexec.new()
    |> glexec.with_stdin(glexec.StdinPipe)
    |> glexec.with_stdout(
      glexec.StdoutFun(fn(_atom, _int, string) {
        case string {
          "bestmove" <> move -> {
            let assert Ok(move) =
              list.first(string.split(string.trim(move), " "))
            actor.send(actor, SendBotMove(move))
          }
          _ -> Nil
        }
      }),
    )
  let assert Ok(glexec.Pids(_pid, ospid)) =
    run_async(options, fairy_stockfish_command)
  actor.send(actor, SetOsPid(ospid))
  Ok(actor)
}
