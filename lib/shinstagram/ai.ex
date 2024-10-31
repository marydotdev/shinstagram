# defmodule Shinstagram.AI do
#   require Logger

#   def parse_chat({:ok, %{choices: [%{"message" => %{"content" => content}} | _]}}),
#     do: {:ok, content}

#   def parse_chat({:error, %{"error" => %{"message" => message}}}), do: {:error, message}

#   @doc """
#   Saves a file to local storage instead of R2/S3
#   """
#   def save_r2(uuid, image_url) do
#     try do
#       # Add http:// if missing from the URL
#       url = if String.contains?(image_url, "://"), do: image_url, else: "https://#{image_url}"

#       # Create uploads directory if it doesn't exist
#       uploads_dir = Path.join(["priv", "static", "uploads"])
#       File.mkdir_p!(uploads_dir)

#       # Download image with error handling
#       case Req.get(url) do
#         {:ok, %{status: 200, body: image_binary}} ->
#           # Save file locally
#           file_name = "prediction-#{uuid}.png"
#           file_path = Path.join(uploads_dir, file_name)

#           case File.write(file_path, image_binary) do
#             :ok ->
#               public_path = "/uploads/#{file_name}"
#               {:ok, public_path}
#             {:error, reason} ->
#               Logger.error("Failed to write image file: #{inspect(reason)}")
#               {:error, "Failed to save image"}
#           end

#         {:ok, %{status: status}} ->
#           Logger.error("Failed to download image, status: #{status}")
#           {:error, "Failed to download image"}

#         {:error, reason} ->
#           Logger.error("Failed to download image: #{inspect(reason)}")
#           {:error, "Failed to download image"}
#       end
#     rescue
#       e ->
#         Logger.error("Failed to save image: #{inspect(e)}")
#         {:error, "Failed to save image"}
#     end
#   end

#   def gen_image({:ok, image_prompt}), do: gen_image(image_prompt)

#   @doc """
#   Generates an image given a prompt. Returns {:ok, url} or {:error, error}.
#   """
#   def gen_image(image_prompt) when is_binary(image_prompt) do
#     model = Replicate.Models.get!("stability-ai/stable-diffusion")

#     version =
#       Replicate.Models.get_version!(
#         model,
#         "ac732df83cea7fff18b8472768c88ad041fa750ff7682a21affe81863cbe77e4"
#       )

#     {:ok, prediction} = Replicate.Predictions.create(version, %{prompt: image_prompt})
#     {:ok, prediction} = Replicate.Predictions.wait(prediction)

#     prediction.output
#     |> List.first()
#     |> save_r2(prediction.id)
#   end

#   def chat_completion(text) do
#     text
#     |> OpenAI.chat_completion()
#     |> parse_chat()
#   end
# end
# The error is occurring in the AI module's save_r2 function. Here's the improved version:

defmodule Shinstagram.AI do
  require Logger

  def parse_chat({:ok, %{choices: [%{"message" => %{"content" => content}} | _]}}),
    do: {:ok, content}

  def parse_chat({:error, %{"error" => %{"message" => message}}}), do: {:error, message}

  def save_r2(uuid, image_url) do
    try do
      # Add more robust URL validation
      url = case URI.parse(image_url) do
        %URI{scheme: nil} -> "https://#{image_url}"
        %URI{scheme: scheme} when scheme in ["http", "https"] -> image_url
        _ ->
          Logger.error("Invalid URL scheme: #{image_url}")
          raise "Invalid URL scheme"
      end

      # Create uploads directory if it doesn't exist
      uploads_dir = Path.join(["priv", "static", "uploads"])
      File.mkdir_p!(uploads_dir)

      # Add timeout and retry logic for image download
      case download_with_retry(url, 3) do
        {:ok, image_binary} ->
          file_name = "prediction-#{uuid}.png"
          file_path = Path.join(uploads_dir, file_name)

          case File.write(file_path, image_binary) do
            :ok ->
              public_path = "/uploads/#{file_name}"
              {:ok, public_path}
            {:error, reason} ->
              Logger.error("Failed to write image file: #{inspect(reason)}")
              {:error, "Failed to save image to disk"}
          end

        {:error, reason} ->
          Logger.error("Failed to download image after retries: #{inspect(reason)}")
          {:error, "Failed to download image"}
      end
    rescue
      e ->
        Logger.error("Failed to save image: #{inspect(e)}")
        {:error, "Image processing failed"}
    end
  end

  def gen_image(image_prompt) when is_binary(image_prompt) do
    model = Replicate.Models.get!("stability-ai/stable-diffusion")

    version =
      Replicate.Models.get_version!(
        model,
        "ac732df83cea7fff18b8472768c88ad041fa750ff7682a21affe81863cbe77e4"
      )

    case Replicate.Predictions.create(version, %{prompt: image_prompt}) do
      {:ok, prediction} ->
        case Replicate.Predictions.wait(prediction) do
          {:ok, prediction} ->
            case prediction.output do
              [url | _] when is_binary(url) -> save_r2(prediction.id, url)
              _ ->
                Logger.error("Invalid prediction output format")
                {:error, "Invalid prediction output"}
            end
          {:error, reason} ->
            Logger.error("Prediction wait failed: #{inspect(reason)}")
            {:error, "Failed to generate image"}
        end
      {:error, reason} ->
        Logger.error("Failed to create prediction: #{inspect(reason)}")
        {:error, "Failed to start image generation"}
    end
  end

  def chat_completion(text) do
    text
    |> OpenAI.chat_completion()
    |> parse_chat()
  end

  # New helper function for retrying downloads
  defp download_with_retry(url, attempts) do
    download_with_retry(url, attempts, 1)
  end

  defp download_with_retry(_url, max_attempts, current_attempt) when current_attempt > max_attempts do
    {:error, "Max retry attempts reached"}
  end

  defp download_with_retry(url, max_attempts, current_attempt) do
    Logger.info("Attempting to download image (attempt #{current_attempt}/#{max_attempts})")

    case Req.get(url, receive_timeout: 15_000) do
      {:ok, %{status: 200, body: image_binary}} ->
        {:ok, image_binary}

      {:ok, %{status: status}} ->
        Logger.warn("Failed download attempt #{current_attempt} with status: #{status}")
        Process.sleep(current_attempt * 1000) # Exponential backoff
        download_with_retry(url, max_attempts, current_attempt + 1)

      {:error, %Mint.TransportError{reason: :nxdomain}} ->
        Logger.warn("DNS resolution failed for #{url}")
        {:error, "DNS resolution failed"}

      {:error, reason} ->
        Logger.warn("Download attempt #{current_attempt} failed: #{inspect(reason)}")
        Process.sleep(current_attempt * 1000)
        download_with_retry(url, max_attempts, current_attempt + 1)
    end
  end
end
