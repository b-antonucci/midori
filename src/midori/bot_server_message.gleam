import gleam/erlang/process.{type Subject}
import midori/game_manager_message

pub type BotServerMessage {
  RequestBotMove(gameid: String, fen: String)
  SendBotMove(move: String)
  SetOsPid(pid: Int)
  SetGameManagerSubject(
    subject: Subject(game_manager_message.GameManagerMessage),
  )
}
