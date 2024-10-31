defmodule ShinstagramWeb.ProfileLive.Show do
  require Logger
  use ShinstagramWeb, :live_view

  alias Shinstagram.Profiles
  alias Shinstagram.Timeline
  alias Shinstagram.Logs
  alias Shinstagram.Logs.Log

  @impl true
  def mount(%{"username" => username}, _session, socket) do
    if connected?(socket) do
      Timeline.subscribe()
      Phoenix.PubSub.subscribe(Shinstagram.PubSub, "feed")
    end

    profile = Profiles.get_profile_by_username!(username)
    logs = Logs.list_logs_by_profile(profile)

    {:ok,
     socket
     |> assign(profile: profile)
     |> assign(:page_title, "View #{profile.name}'s profile on Shinstagram")
     |> stream(:posts, Timeline.list_posts_by_profile(profile))
     |> stream(:logs, logs)}
  end

  def handle_info({"profile_activity", _event, log}, socket) do
    if log.profile_id == socket.assigns.profile.id do
      {:noreply, socket |> stream_insert(:logs, log, at: 0)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:post_created, post}, socket) do
    if post.profile.id == socket.assigns.profile.id do
      {:noreply, socket |> stream_insert(:posts, post, at: 0)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:post_updated, post}, socket) do
    {:noreply, socket}
  end

  def handle_event("wake-up", _, %{assigns: %{profile: profile}} = socket) do
    {:ok, profile} = Shinstagram.ProfileSupervisor.add_profile(profile)
    {:noreply, socket |> assign(profile: profile)}
  end

  def handle_event("sleep", %{"pid" => pid_string}, socket) do
    clean_pid = pid_string
      |> String.replace(~r/#PID<(.+)>/, "\\1")

    case Shinstagram.Agents.Profile.shutdown_profile(socket.assigns.profile, clean_pid) do
      {:ok, _updated_profile} ->
        {:noreply, socket}

      {:error, reason} ->
        Logger.error("Failed to shutdown profile: #{inspect(reason)}")
        {:noreply, socket}
    end
  end
end
