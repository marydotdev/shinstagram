# defmodule Shinstagram.Agents.Profile do
#   require Logger

#   @moduledoc """
#   """
#   use GenServer, restart: :transient
#   alias Shinstagram.Timeline
#   import AI
#   import Shinstagram.AI
#   alias Shinstagram.Profiles

#   # what our agent likes doing
#   @actions_probabilities [{:post, 0.7}, {:look, 0.2}, {:sleep, 0.1}]
#   # how fast our agent thinks
#   @cycle_time 1000
#   # channel that agents subscribe to
#   @channel "feed"

#   def start_link(profile) do
#     {:ok, pid} = GenServer.start_link(__MODULE__, %{profile: profile, last_action: nil})
#     {:ok, pid}
#   end

#   def init(state) do
#     Phoenix.PubSub.subscribe(Shinstagram.PubSub, @channel)
#     broadcast({:thought, "🛌", "I'm waking up!"}, state.profile)

#     Process.send_after(self(), :think, 3000)
#     {:ok, state}
#   end

#   # 💭 The mind of a profile
#   def handle_info(:think, %{profile: profile} = state) do
#     action = get_next_action()
#     broadcast({:thought, "💭", "I want to #{action |> Atom.to_string()}"}, profile)

#     Process.send_after(self(), action, @cycle_time)
#     {:noreply, state}
#   end

#   def handle_info(:sleep, %{profile: profile} = state) do
#     broadcast({:action, "💤", "I'm going back to sleep..."}, profile)
#     Shinstagram.Profiles.update_profile(profile, %{pid: nil})

#     {:stop, :normal, state}
#   end

#   def handle_info(:look, %{profile: profile} = state) do
#     broadcast({:thought, "🤳", "I'm scrolling at the feed"}, profile)
#     number_of_posts = 1..10 |> Enum.random()

#     for post <- Timeline.list_recent_posts(number_of_posts) do
#       evaluate(profile, post)
#       |> handle_decision()
#     end

#     broadcast({:thought, "📵", "I'm done scrolling at the feed"}, profile)
#     Process.send_after(self(), :think, @cycle_time)
#     {:noreply, %{state | last_action: :look}}
#   end

#   # def handle_info(:post, %{profile: profile} = state) do
#   #   if can_post_again?(profile) do
#   #     with {:ok, image_prompt} <- gen_image_prompt(profile),
#   #          {:ok, location} <- gen_location(image_prompt, profile),
#   #          {:ok, caption} <- gen_caption(image_prompt, profile),
#   #          {:ok, image_url} <- gen_image(image_prompt),
#   #          {:ok, _post} <- create_post(profile, image_url, image_prompt, caption, location, state) do
#   #       Process.send_after(self(), :think, @cycle_time)
#   #       {:noreply, %{state | last_action: :post}}
#   #     end
#   #   else
#   #     broadcast({:thought, "🚫", "I can't post, posted too recently!"}, profile)
#   #     Process.send_after(self(), :think, @cycle_time)
#   #     {:noreply, %{state | last_action: :post}}
#   #   end
#   # end

#   def handle_info(:post, %{profile: profile} = state) do
#     try do
#       case Timeline.gen_post(profile) do
#         {:ok, post} ->
#           broadcast(post, :post_created)
#           {:noreply, state}

#         {:error, reason} ->
#           # Log the error
#           Logger.error("Failed to generate post: #{inspect(reason)}")

#           # Create an error log for the user
#           Shinstagram.Logs.create_log!(%{
#             event: "error",
#             message: "Failed to create post: #{reason}",
#             emoji: "❌",
#             profile_id: profile.id
#           })

#           # Return proper GenServer format
#           {:noreply, state}
#       end
#     rescue
#       e ->
#         Logger.error("Error in post generation: #{inspect(e)}")
#         Shinstagram.Logs.create_log!(%{
#           event: "error",
#           message: "An unexpected error occurred",
#           emoji: "❌",
#           profile_id: profile.id
#         })
#         {:noreply, state}
#     end
#   end

#   def handle_info({"profile_activity", _, _}, socket) do
#     {:noreply, socket}
#   end

#   # 🗣️ The voice of the agent
#   defp broadcast({event, emoji, message}, profile) do
#     log =
#       Shinstagram.Logs.create_log!(%{
#         event: event |> Atom.to_string(),
#         message: message,
#         profile_id: profile.id,
#         emoji: emoji
#       })

#     Phoenix.PubSub.broadcast(Shinstagram.PubSub, @channel, {"profile_activity", event, log})
#   end

#   defp broadcast({:ok, text}, {event, emoji, message}, profile) do
#     broadcast({event, emoji, message}, profile)
#     {:ok, text}
#   end

#   # 🧠 The pre-frontal cortex
#   defp evaluate(profile, post) do
#     broadcast({:thought, "👀", "I'm evaluating post:#{post.id}"}, profile)
#     poster = Profiles.get_profile!(post.profile_id)

#     {:ok, result} =
#       ~l"""
#       model: gpt-3.5-turbo
#       system: You are a user on a photo sharing social site (called shinstagram).
#       Here's some information about you:
#       - Your username is #{profile.username}.
#       - Your profile summary is #{profile.summary}.
#       - Your vibe is #{profile.vibe}.

#       In this moment, you are looking at a post.
#       - The photo in the post is of #{post.photo_prompt}.
#       - The post is captioned '#{post.caption}'
#       - It was taken in #{post.location}.
#       - The post was made by #{poster.username}.

#       The three most recent comments on the post are:
#       #{post.comments |> Enum.slice(0..3) |> Enum.map(& &1.body) |> Enum.join("\n- ")}

#       You #{if profile.id in [post.likes |> Enum.map(& &1.profile_id)], do: "have", else: "have not"} liked the post already.

#       What does your profile choose to do? If you recently commented or liked the photo,
#       you probably want to ignore the photo now.

#       Your decision options are: [like, comment, ignore] the photo. Keep the explanation short.
#       Answer in the format <decision>;;<explanation-for-why>
#       """
#       |> chat_completion()

#     [decision, explanation] = String.split(result, ";;")
#     {post, profile, decision, explanation}
#   end

#   # Internal logic
#   defp comment(profile, post) do
#     {:ok, comment_body} = Timeline.gen_comment(profile, post)

#     {:ok, post} =
#       Timeline.create_comment(profile, post, %{body: comment_body |> String.replace("\"", "")})

#     broadcast({:action, "💬", "Just commented '#{comment_body}' on post:#{post.id}"}, profile)
#   end

#   defp handle_decision({post, profile, decision, explanation}) do
#     broadcast(
#       {:thought, "💭", "I want to #{decision} on post:#{post.id} because '#{explanation}'"},
#       profile
#     )

#     case decision do
#       "like" -> Timeline.create_like(profile, post)
#       "comment" -> comment(profile, post)
#       _ -> nil
#     end
#   end

#   defp get_next_action() do
#     @actions_probabilities
#     |> Enum.flat_map(fn {action, probability} ->
#       List.duplicate(action, Float.round(probability * 100) |> trunc())
#     end)
#     |> Enum.random()
#   end

#   # def shutdown_profile(pid, timeout \\ 30_000)

#   # def shutdown_profile(pid_string, timeout) when is_binary(pid_string) do
#   #   pid =
#   #     pid_string
#   #     |> String.replace("#PID", "")
#   #     |> String.to_charlist()
#   #     |> :erlang.list_to_pid()

#   #   profile = Profiles.get_profile_by_pid!(pid)
#   #   broadcast({:action, "💤", "I'm going back to sleep..."}, profile)
#   #   GenServer.stop(pid, :normal, timeout)
#   #   Profiles.update_profile(profile, %{pid: nil})
#   # end

#   # def shutdown_profile(pid, timeout) do
#   #   profile = Profiles.get_profile_by_pid!(pid)
#   #   broadcast({:action, "💤", "I'm going back to sleep..."}, profile)
#   #   GenServer.stop(pid, :normal, timeout)
#   #   Profiles.update_profile(profile, %{pid: nil})
#   # end
#    @doc """
#   Safely shuts down a profile's process and updates its database record.
#   """
#   def shutdown_profile(profile, pid) do
#     # First update the database record to remove the PID
#     {:ok, profile} = Shinstagram.Profiles.update_profile(profile, %{pid: nil})

#     # Then try to stop the process if it exists
#     try do
#       case Process.alive?(pid) do
#         true ->
#           GenServer.stop(pid, :normal)
#         false ->
#           Logger.info("Process #{inspect(pid)} already terminated")
#       end
#     rescue
#       e ->
#         Logger.warning("Failed to stop profile process: #{inspect(e)}")
#     end

#     # Broadcast the update regardless of process status
#     broadcast(profile, :profile_updated)

#     {:ok, profile}
#   end

#   # helpers
#   defp gen_image_prompt(profile) do
#     profile
#     |> Timeline.gen_image_prompt()
#     |> broadcast({:thought, "🖼️", "I picked a photo subject"}, profile)
#   end

#   defp gen_location(image_prompt, profile) do
#     {:ok, location} = Timeline.gen_location(image_prompt)
#     broadcast({:action, "📸 ", "I took a photo in #{location} of #{image_prompt}"}, profile)
#     {:ok, location}
#   end

#   defp gen_caption(image_prompt, profile) do
#     {:ok, caption} = image_prompt |> Timeline.gen_caption(profile)
#     broadcast({:thought, "📝", "I wrote a caption: '#{caption}'"}, profile)
#     {:ok, caption}
#   end

#   defp create_post(profile, image_url, image_prompt, caption, location, state) do
#     {:ok, post} =
#       profile
#       |> Timeline.create_post(%{
#         photo: image_url,
#         photo_prompt: image_prompt,
#         caption: caption,
#         location: location
#       })

#     broadcast(
#       {:new_post, "🖼️", "I'm posting the post:#{post.id}! I hope it goes well!"},
#       profile
#     )

#     Process.send_after(self(), :think, @cycle_time)
#     {:noreply, %{state | last_action: :post}}
#   end

#   defp can_post_again?(profile) do
#     if is_new_profile?(profile) do
#       true
#     else
#       case Timeline.list_posts_by_profile(profile, 1) do
#         [] ->
#           true

#         [last_post] ->
#           NaiveDateTime.diff(NaiveDateTime.utc_now(), last_post.inserted_at, :minute) >= 5
#       end
#     end
#   end

#   defp is_new_profile?(profile) do
#     NaiveDateTime.diff(NaiveDateTime.utc_now(), profile.inserted_at, :minute) < 20
#   end
# end

defmodule Shinstagram.Agents.Profile do
  require Logger

  @moduledoc """
  Agent that represents a profile's autonomous behavior on the platform.
  """
  use GenServer, restart: :transient
  alias Shinstagram.Timeline
  import AI
  import Shinstagram.AI
  alias Shinstagram.{Profiles, Logs}

  # Behavior configuration
  @actions_probabilities [{:post, 0.7}, {:look, 0.2}, {:sleep, 0.1}]
  @cycle_time 1000
  @channel "feed"

  def start_link(profile) do
    {:ok, pid} = GenServer.start_link(__MODULE__, %{profile: profile, last_action: nil})
    {:ok, pid}
  end

  def init(state) do
    Phoenix.PubSub.subscribe(Shinstagram.PubSub, @channel)
    broadcast({:thought, "🛌", "I'm waking up!"}, state.profile)

    Process.send_after(self(), :think, 3000)
    {:ok, state}
  end

  # Handle thinking cycle
  def handle_info(:think, %{profile: profile} = state) do
    action = get_next_action()
    broadcast({:thought, "💭", "I want to #{action |> Atom.to_string()}"}, profile)

    Process.send_after(self(), action, @cycle_time)
    {:noreply, state}
  end

  # Handle sleep action
  def handle_info(:sleep, %{profile: profile} = state) do
    broadcast({:action, "💤", "I'm going back to sleep..."}, profile)
    Profiles.update_profile(profile, %{pid: nil})

    {:stop, :normal, state}
  end

  # Handle look action
  def handle_info(:look, %{profile: profile} = state) do
    broadcast({:thought, "🤳", "I'm scrolling at the feed"}, profile)
    number_of_posts = 1..10 |> Enum.random()

    try do
      for post <- Timeline.list_recent_posts(number_of_posts) do
        evaluate(profile, post)
        |> handle_decision()
      end

      broadcast({:thought, "📵", "I'm done scrolling at the feed"}, profile)
      Process.send_after(self(), :think, @cycle_time)
      {:noreply, %{state | last_action: :look}}
    rescue
      e ->
        Logger.error("Error during look action: #{inspect(e)}")
        Process.send_after(self(), :think, @cycle_time)
        {:noreply, state}
    end
  end

  # Handle post action
  def handle_info(:post, %{profile: profile} = state) do
    if can_post_again?(profile) do
      try do
        with {:ok, image_prompt} <- gen_image_prompt(profile),
             {:ok, location} <- gen_location(image_prompt, profile),
             {:ok, caption} <- gen_caption(image_prompt, profile),
             {:ok, image_url} <- gen_image(image_prompt) do
          case Timeline.create_post(profile, %{
            photo: image_url,
            photo_prompt: image_prompt,
            caption: caption,
            location: location
          }) do
            {:ok, post} ->
              broadcast({:new_post, "🖼️", "I'm posting the post:#{post.id}! I hope it goes well!"}, profile)
              Process.send_after(self(), :think, @cycle_time)
              {:noreply, %{state | last_action: :post}}

            {:error, reason} ->
              Logger.error("Failed to create post: #{inspect(reason)}")
              Process.send_after(self(), :think, @cycle_time)
              {:noreply, state}
          end
        else
          {:error, reason} ->
            Logger.error("Failed in post generation: #{inspect(reason)}")
            Process.send_after(self(), :think, @cycle_time)
            {:noreply, state}
        end
      rescue
        e ->
          Logger.error("Error in post generation: #{inspect(e)}")
          Process.send_after(self(), :think, @cycle_time)
          {:noreply, state}
      end
    else
      broadcast({:thought, "🚫", "I can't post, posted too recently!"}, profile)
      Process.send_after(self(), :think, @cycle_time)
      {:noreply, %{state | last_action: :post}}
    end
  end

  def handle_info({"profile_activity", _, _}, state) do
    {:noreply, state}
  end

   @doc """
  Safely shuts down a profile's process and updates its database record.
  Can handle both PID and string PID formats.
  """
  def shutdown_profile(profile, pid) when is_binary(pid) do
    # Convert string PID to actual PID
    actual_pid =
      pid
      |> String.replace("#PID<", "")
      |> String.replace(">", "")
      |> String.to_charlist()
      |> :erlang.list_to_pid()

    shutdown_profile(profile, actual_pid)
  end

  def shutdown_profile(%{id: _} = profile, pid) when is_pid(pid) do
    # First update the database record
    {:ok, updated_profile} = Profiles.update_profile(profile, %{pid: nil})

    # Create shutdown log
    broadcast({:action, "💤", "I'm going back to sleep..."}, profile)

    # Try to stop the process if it exists
    try do
      case Process.alive?(pid) do
        true ->
          GenServer.stop(pid, :normal)
        false ->
          Logger.info("Process #{inspect(pid)} already terminated")
      end
    rescue
      e ->
        Logger.warning("Failed to stop profile process: #{inspect(e)}")
    end

    {:ok, updated_profile}
  end

  # Catch-all clause for debugging
  def shutdown_profile(profile, pid) do
    Logger.error("Invalid arguments to shutdown_profile: profile=#{inspect(profile)}, pid=#{inspect(pid)}")
    {:error, :invalid_arguments}
  end

  # Private functions

  defp broadcast({event, emoji, message}, profile) do
    log = Logs.create_log!(%{
      event: event |> Atom.to_string(),
      message: message,
      profile_id: profile.id,
      emoji: emoji
    })

    Phoenix.PubSub.broadcast(Shinstagram.PubSub, @channel, {"profile_activity", event, log})
  end

  defp broadcast({:ok, text}, {event, emoji, message}, profile) do
    broadcast({event, emoji, message}, profile)
    {:ok, text}
  end

  defp evaluate(profile, post) do
    broadcast({:thought, "👀", "I'm evaluating post:#{post.id}"}, profile)
    poster = Profiles.get_profile!(post.profile_id)

    {:ok, result} =
      ~l"""
      model: gpt-3.5-turbo
      system: You are a user on a photo sharing social site (called shinstagram).
      Here's some information about you:
      - Your username is #{profile.username}.
      - Your profile summary is #{profile.summary}.
      - Your vibe is #{profile.vibe}.

      In this moment, you are looking at a post.
      - The photo in the post is of #{post.photo_prompt}.
      - The post is captioned '#{post.caption}'
      - It was taken in #{post.location}.
      - The post was made by #{poster.username}.

      The three most recent comments on the post are:
      #{post.comments |> Enum.slice(0..3) |> Enum.map(& &1.body) |> Enum.join("\n- ")}

      You #{if profile.id in [post.likes |> Enum.map(& &1.profile_id)], do: "have", else: "have not"} liked the post already.

      What does your profile choose to do? If you recently commented or liked the photo,
      you probably want to ignore the photo now.

      Your decision options are: [like, comment, ignore] the photo. Keep the explanation short.
      Answer in the format <decision>;;<explanation-for-why>
      """
      |> chat_completion()

    [decision, explanation] = String.split(result, ";;")
    {post, profile, decision, explanation}
  end

  # Action helpers
  defp gen_image_prompt(profile) do
    profile
    |> Timeline.gen_image_prompt()
    |> broadcast({:thought, "🖼️", "I picked a photo subject"}, profile)
  end

  defp gen_location(image_prompt, profile) do
    {:ok, location} = Timeline.gen_location(image_prompt)
    broadcast({:action, "📸 ", "I took a photo in #{location} of #{image_prompt}"}, profile)
    {:ok, location}
  end

  defp gen_caption(image_prompt, profile) do
    {:ok, caption} = image_prompt |> Timeline.gen_caption(profile)
    broadcast({:thought, "📝", "I wrote a caption: '#{caption}'"}, profile)
    {:ok, caption}
  end

  defp handle_decision({post, profile, decision, explanation}) do
    broadcast(
      {:thought, "💭", "I want to #{decision} on post:#{post.id} because '#{explanation}'"},
      profile
    )

    case decision do
      "like" -> Timeline.create_like(profile, post)
      "comment" -> comment(profile, post)
      _ -> nil
    end
  end

  defp comment(profile, post) do
    {:ok, comment_body} = Timeline.gen_comment(profile, post)

    {:ok, post} =
      Timeline.create_comment(profile, post, %{body: comment_body |> String.replace("\"", "")})

    broadcast({:action, "💬", "Just commented '#{comment_body}' on post:#{post.id}"}, profile)
  end

  defp get_next_action() do
    @actions_probabilities
    |> Enum.flat_map(fn {action, probability} ->
      List.duplicate(action, Float.round(probability * 100) |> trunc())
    end)
    |> Enum.random()
  end

  defp can_post_again?(profile) do
    if is_new_profile?(profile) do
      true
    else
      case Timeline.list_posts_by_profile(profile, 1) do
        [] -> true
        [last_post] ->
          NaiveDateTime.diff(NaiveDateTime.utc_now(), last_post.inserted_at, :minute) >= 5
      end
    end
  end

  defp is_new_profile?(profile) do
    NaiveDateTime.diff(NaiveDateTime.utc_now(), profile.inserted_at, :minute) < 20
  end
end
