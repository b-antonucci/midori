import gleam/erlang/process.{type Subject}
import gleam/option.{type Option}

pub type UserManagerMessage {
  AddUser(reply_with: Subject(Result(String, String)))
  RemoveUser(reply_with: Subject(Result(Nil, String)), id: String)
  AddGameToUser(
    reply_with: Subject(Result(Nil, String)),
    user_id: String,
    game_id: String,
  )
  GetUserGame(
    reply_with: Subject(Result(Option(String), String)),
    user_id: String,
  )
  ConfirmUserExists(reply_with: Subject(Result(Nil, String)), id: String)
}
