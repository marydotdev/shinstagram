defmodule Shinstagram.Utils do
  require Logger

  @image_model "stability-ai/sdxl"

  def parse_chat({:ok, %{choices: [%{"message" => %{"content" => content}} | _]}}) do
    {:ok, content}
  end

  def save_local(uuid, image_url) do
    # Create uploads directory if it doesn't exist
    uploads_dir = Path.join(["priv", "static", "uploads"])
    File.mkdir_p!(uploads_dir)

    # Download image and save it locally
    image_binary = Req.get!(image_url).body
    file_name = "prediction-#{uuid}.png"
    file_path = Path.join(uploads_dir, file_name)

    case File.write(file_path, image_binary) do
      :ok ->
        public_path = "/uploads/#{file_name}"
        {:ok, public_path}
      {:error, reason} ->
        Logger.error("Failed to save image: #{inspect(reason)}")
        {:error, "Failed to save image"}
    end
  end

  def gen_image({:ok, image_prompt}), do: gen_image(image_prompt)

  @doc """
  Generates an image given a prompt. Returns {:ok, url} or {:error, error}.
  """
  def gen_image(image_prompt) when is_binary(image_prompt) do
    Logger.info("Generating image for #{image_prompt}")
    model = Replicate.Models.get!(@image_model)
    version = Replicate.Models.get_latest_version!(model)

    case Replicate.Predictions.create(version, %{prompt: image_prompt}) do
      {:ok, prediction} ->
        case Replicate.Predictions.wait(prediction) do
          {:ok, prediction} ->
            Logger.info("Image generated: #{prediction.output}")
            result = List.first(prediction.output)
            save_local(prediction.id, result)

          {:error, error} ->
            Logger.error("Failed to wait for prediction: #{inspect(error)}")
            {:error, "Failed to generate image"}
        end

      {:error, error} ->
        Logger.error("Failed to create prediction: #{inspect(error)}")
        {:error, "Failed to start image generation"}
    end
  end

  def chat_completion(text) do
    text
    |> OpenAI.chat_completion()
    |> Utils.parse_chat()
  end
end
