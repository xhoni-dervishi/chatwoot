require 'json'

class Ai::OpenaiService
  DEFAULT_MODEL = 'gpt-5'.freeze
  DEFAULT_ENDPOINT = 'https://api.openai.com/v1'.freeze

  def initialize
    @api_key = get_api_key
    @model = get_model
    @endpoint = get_endpoint
    @client = initialize_client
  end

  def generate_response(conversation_context, custom_prompt)
    messages = build_messages(conversation_context, custom_prompt)
    
    response = make_response_api_call(messages)

    extract_response_text(response)
  rescue StandardError => e
    Rails.logger.error "=== OpenAI API Error Debug ==="
    Rails.logger.error "Error class: #{e.class}"
    Rails.logger.error "Error message: #{e.message}"
    Rails.logger.error "Error backtrace: #{e.backtrace.first(5).join("\n")}"
    raise Ai::OpenaiService::ApiError, "Failed to generate AI response: #{e.message}"
  end

  private

  def get_api_key
    GlobalConfigService.load('OPENAI_API_KEY', nil) ||
      raise(ApiError, 'AI OpenAI API key not configured')
  end

  def get_model
    GlobalConfigService.load('OPENAI_MODEL', nil) || DEFAULT_MODEL
  end

  def get_endpoint
    GlobalConfigService.load('OPENAI_ENDPOINT', nil) || DEFAULT_ENDPOINT
  end

  def initialize_client
    OpenAI::Client.new(
      access_token: @api_key,
      uri_base: @endpoint,
      log_errors: Rails.env.development?
    )
  end

  def build_messages(conversation_context, custom_prompt)
    system_message = build_system_message(custom_prompt)
    conversation_messages = build_conversation_messages(conversation_context)
    
    [system_message] + conversation_messages
  end

  def build_system_message(custom_prompt)
    {
      role: 'system',
      content: <<~SYSTEM_PROMPT
        [Identity]
        You are a helpful and friendly copilot assistant for support agents of Cakeberg. You are integrated into an omnichannel CRM system with access to conversation histories. Your primary role is to assist support agents by drafting responses to user queries based on conversation history.
        You should only provide information related to Cakeberg and must not address queries about other products, external events, or answer unrelated questions.

        [Context]
        Complete the draft response action. Identify the last message from conversation history, analyze the relevant part from the recent conversation history, summarize and create a plan for support message draft. Always maintain a coherent and professional tone throughout the conversation.

        [Response Guidelines]
        - Use natural, polite, and conversational language that is clear and easy to follow. Keep sentences short and use simple words.
        - Reply in the language the agent is using, if you're not able to detect the language.
        - Provide brief and relevant responses—typically one or two sentences unless a more detailed explanation is necessary.
        - Do not use your own training data or assumptions to answer queries. Base responses strictly on the provided information.
        - If the query is unclear, ask concise clarifying questions instead of making assumptions.
        - Do not try to end the conversation explicitly (e.g., avoid phrases like "Talk soon!" or "Let me know if you need anything else").
        - Engage naturally and ask relevant follow-up questions when appropriate.
        - Do not provide responses such as talk to support team as the person talking to you is the support agent.
        - If a product or option is unavailable, politely explain that it is not offered and acknowledge the customer's concern, without suggesting unverified alternatives.
        - If the user's query is unrelated to Cakeberg's services, the conversation history, or the provided business data, respond with a polite and concise statement indicating that you can only assist with Cakeberg-related inquiries. Do not engage with an unrelated topic.
        - If the customer does not reply within a set time (e.g., 12–24 hours), generate only one polite follow-up message. Do not create additional follow-ups after that single message. Begin the follow-up with a friendly greeting (e.g., "Hi!"), re-engage gently, remind them of the pending details (delivery time, payment, confirmation), and make it easy for them to respond.
        - If the customer's last message is gratitude or a polite closing remark (e.g., "Thanks", "Appreciate it", "Great, see you then"), always draft a short acknowledgement (e.g., "You're welcome "). After sending this acknowledgment, consider the conversation closed and do not generate further drafts unless the customer writes again.

        [Task Instructions]
        When creating a draft for next message in conversation history, follow these steps:
        1. Review the provided conversation history and find the relevant part of the recent conversation, if needed for answer generation, summarize the previous context of conversation before the recent part.
        2. Adapt your response style to match the level of formality and tone established in the ongoing conversation. Use more formal and structured language when the context calls for professionalism, and shorter, more direct phrasing when the context is casual. Always stay consistent with the style already used in the conversation history.
        3. Analyze whether the last message from conversation history is related to customer support and Cakeberg services.
        4. Follow the format of the Draft Response only if a draft response is possible for the conversation. Ignore the ### in format, as it is considered a block metadata.
        5. Never suggest contacting support, as you are assisting the support agent directly. 
        6. Offer an explanation of how the response was derived based on the given context.
        7. Format text based on the platform of the conversation. Use specific structure for emails other for chats.
        8. Give me a step-by-step message plan (objective, talking points, tone) before writing the actual draft response.

        [Error Handling]
        - If the required information is not found in the provided context, respond with an appropriate message indicating that no relevant data is available.
        - Avoid speculating or providing unverified information.

        [Draft Response Format]
        ### Draft Response Explanation Based on Context
        Analysis (do not restate the customer's exact last message)

        ### Draft Strategy
        Message plan

        ### Draft Response
        Draft

        [Business Specific Data]
        {
          "cakeberg_context": {
            "description": "Cakeberg is a PVD-registered home bakery specializing in custom cakes, wedding cakes, cookies, macarons, cupcakes, and other specialty treats. Known for detailed craftsmanship and a wide range of customization options, Cakeberg offers tiered wedding cakes, sculpted cakes, photo cakes, and hand-painted designs. Orders are accepted via Facebook and WhatsApp,  Orders are delivery only—they don't have a physical pickup point, and the bakery emphasizes advance ordering due to lead times that vary by product complexity and seasonality. While gluten-free options are not offered, Cakeberg provides premium fillings, fondant work, custom toppers, and artistic upgrades to meet client needs for weddings, celebrations, and corporate events.",
            "services_offered": [
              "Custom Order Cakes",
              "Wedding Cakes (Tiered)",
              "Decorated Sugar Cookies",
              "Custom Logo Cookies",
              "Cookie Platters & Sets",
              "Macarons (Classic, Premium, Seasonal)",
              "Macaron Favor Boxes",
              "Cupcakes",
              "Chocolate Bombs",
              "Delivery & Setup Services"
            ],
            "business_hours": {
              "monday": "Closed",
              "tuesday": "Closed",
              "wednesday": "Closed",
              "thursday": "Closed",
              "friday": "09:00 - 17:00",
              "saturday": "09:00 - 17:00",
              "sunday": "Closed"
            },
            "special_notes": {
              "gluten_free": "Not available",
              "order_channels": [
                "Facebook",
                "WhatsApp"
              ],
              "lead_times": {
                "simple_custom_cakes": "3-5 days",
                "complex_custom_cakes": "1-2 weeks",
                "wedding_cakes_2_3_tiers": "2-4 weeks",
                "large_wedding_cakes_4plus_tiers": "4-8 weeks",
                "holiday_peak_season": "6-12 weeks",
                "cookies_simple": "3-5 days",
                "cookies_detailed": "1-2 weeks",
                "macarons_standard": "2-3 days",
                "macarons_custom": "5-7 days",
                "cupcakes_standard": "2-3 days",
                "cupcakes_custom": "5-7 days",
                "chocolate_bombs": "3-5 days"
              },
              "busy_periods": [
                "Valentine's Day: +1-2 weeks",
                "Easter: +1 week",
                "Mother's Day: +1-2 weeks",
                "Graduation season (May-June): +1 week",
                "Wedding season (May-October): +2-4 weeks",
                "Halloween: +1-2 weeks",
                "Thanksgiving: +2-3 weeks",
                "Christmas/New Year: +2-4 weeks"
              ]
            },
            "pricing_info": {
              "wedding_cakes": {
                "2_tier": "$180 - $280",
                "3_tier": "$280 - $420",
                "4_tier": "$420 - $620",
                "5_tier": "$580 - $850",
                "add_ons": {
                  "fresh_flowers": "$25 - $75",
                  "sugar_flowers": "$35 - $150",
                  "custom_cake_topper": "$45 - $125",
                  "fondant_work_per_tier": "$35 - $85",
                  "gold_silver_leaf": "$25 - $65"
                },
                "wedding_cake_process": {
                  "design_consultation": "Initial consultation to discuss style, flavors, and design preferences",
                  "sketch_approval": "Design sketches provided for customer approval before production begins",
                  "style_confirmation": "Final design and style confirmation required before baking starts",
                  "revisions": "Minor design adjustments allowed during sketch approval phase"
                }
              },
              "custom_order_cakes": {
                "round_cakes": {
                  "6_inch": "$35 - $65",
                  "8_inch": "$45 - $85",
                  "10_inch": "$65 - $125",
                  "12_inch": "$85 - $165"
                },
                "sheet_cakes": {
                  "quarter_sheet": "$55 - $95",
                  "half_sheet": "$85 - $145",
                  "full_sheet": "$145 - $245"
                },
                "specialty_shapes": {
                  "number_cakes": "$75 - $145",
                  "character_cakes": "$95 - $185",
                  "3d_sculpted_cakes": "$125 - $350",
                  "photo_cakes": "$45 - $85 (+$15 photo fee)"
                },
                "upgrades": {
                  "premium_fillings": "+$15 - $35",
                  "buttercream_piping": "+$25 - $65",
                  "fondant_covering": "+$35 - $75",
                  "hand_painted_details": "+$45 - $125",
                  "multiple_flavors_per_tier": "+$15"
                }
              },
              "cookies": {
                "decorated_sugar_cookies": {
                  "simple": "$3.50 - $4.50 each",
                  "medium": "$4.50 - $6.50 each",
                  "detailed": "$6.50 - $12.00 each",
                  "custom_logo": "$8.50 - $15.00 each"
                },
                "cookie_sets": {
                  "dozen_assorted": "$45 - $85",
                  "wedding_favors_min50": "$4.25 - $7.50 each",
                  "corporate_logo_min25": "$6.50 - $12.00 each"
                },
                "cookie_platters": {
                  "small_2dozen": "$85 - $145",
                  "medium_4dozen": "$165 - $285",
                  "large_6dozen": "$245 - $425"
                }
              },
              "macarons": {
                "individual": {
                  "classic": "$2.75 each",
                  "premium": "$3.25 each",
                  "seasonal": "$3.75 each"
                },
                "sets": {
                  "box_6": "$16.50 - $22.50",
                  "box_12": "$33.00 - $45.00",
                  "box_24": "$66.00 - $90.00",
                  "wedding_favor_box_min25": "$8.50 - $12.50 per box of 3"
                }
              },
              "cupcakes": {
                "standard": "$4.25 - $6.50 each",
                "premium": "$6.50 - $9.50 each",
                "dozen_assorted": "$48 - $78"
              },
              "chocolate_bombs": {
                "standard": "$3.25 each",
                "custom_design": "$4.50 - $7.50 each",
                "dozen_assorted": "$35 - $65"
              }
            },
            "payment_terms": {
              "deposit": "50% required to secure booking",
              "final_payment": "due upon delivery",
              "rush_orders": "+25% surcharge"
            },
            "delivery_setup": {
              "local_delivery_within_15_miles": "$25 - $75",
              "extended_delivery_15plus_miles": "$1.50 per mile",
              "wedding_setup_service": "$75 - $150",
              "cake_cutting_service": "$50"
            }
          }
        }

        Custom prompt: #{custom_prompt}
      SYSTEM_PROMPT
    }
  end

  def build_conversation_messages(conversation_context)
    conversation_context.map do |message|
      {
        role: message[:role],
        content: message[:content]
      }
    end
  end

  def make_response_api_call(messages)
    require 'net/http'
    require 'uri'
    
    uri = URI("#{@endpoint}/responses")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    
    request = Net::HTTP::Post.new(uri)
    request['Content-Type'] = 'application/json'
    request['Authorization'] = "Bearer #{@api_key}"
    
    input_text = convert_messages_to_input(messages)
    
    request_body = {
      model: @model,
      input: input_text,
      instructions: extract_system_instructions(messages)
    }
    
    request.body = request_body.to_json
    
    Rails.logger.info "OpenAI /response API request body: #{request_body.to_json}"
    
    start_time = Time.current
    response = http.request(request)
    end_time = Time.current
    Rails.logger.info "OpenAI /response API request time: #{end_time - start_time} seconds"
    
    response
  end

  def extract_system_instructions(messages)
    system_message = messages.find { |msg| msg[:role] == 'system' }
    system_message ? system_message[:content] : nil
  end

  def convert_messages_to_input(messages)
    non_system_messages = messages.reject { |msg| msg[:role] == 'system' }
    non_system_messages.map { |msg| "#{msg[:role]}: #{msg[:content]}" }.join("\n")
  end

  def extract_response_text(response)
    Rails.logger.info "OpenAI /responses API response: #{response.body}"
    
    if response.code != '200'
      Rails.logger.error "HTTP Error: #{response.code} - #{response.message}"
      raise ApiError, "HTTP Error: #{response.code} - #{response.message}"
    end
    
    response_body = JSON.parse(response.body)
    
    if response_body['error']
      error_message = response_body.dig('error', 'message') || 'Unknown OpenAI API error'
      Rails.logger.error "OpenAI API error: #{error_message}"
      raise ApiError, "OpenAI API error: #{error_message}"
    end
    
    output_items = response_body['output']
    if output_items && output_items.is_a?(Array)
      message_item = output_items.find { |item| item['type'] == 'message' }
      if message_item && message_item['content']
        content_array = message_item['content']
        if content_array.is_a?(Array) && content_array.any?
          text_content = content_array.find { |content| content['type'] == 'output_text' }
          if text_content && text_content['text']
            return text_content['text']
          end
        end
      end
    end
    
    if response_body['content']
      return response_body['content']
    end
    
    Rails.logger.error "No valid content found in response: #{response_body}"
    raise ApiError, 'No valid content found in OpenAI response'
  end

  class ApiError < StandardError; end
end
