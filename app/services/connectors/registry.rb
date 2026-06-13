module Connectors
  # The catalogue of available providers. Add a roadmap connector by
  # writing a Provider subclass and registering its key here.
  module Registry
    module_function

    def providers
      {
        "http_json" => Connectors::HttpJsonProvider,
        "slack_webhook" => Connectors::SlackWebhookProvider,
        "msg91" => Connectors::Msg91Provider,
        "razorpay" => Connectors::RazorpayProvider,
        # Commercial lane — wave 1 (effector + sync, static credentials)
        "whatsapp_cloud" => Connectors::WhatsappCloudProvider,
        "shopify" => Connectors::ShopifyProvider,
        "stripe" => Connectors::StripeProvider,
        "hubspot" => Connectors::HubspotProvider,
        "zendesk" => Connectors::ZendeskProvider,
        "sendgrid" => Connectors::SendgridProvider,
        "twilio_sms" => Connectors::TwilioSmsProvider,
        "telegram_bot" => Connectors::TelegramBotProvider,
        # Commercial lane — wave 2 (CPaaS, payments, support, CRM, marketing, e-commerce, forms, iPaaS bridges)
        "msteams_webhook" => Connectors::MicrosoftTeamsWebhookProvider,
        "googlechat_webhook" => Connectors::GoogleChatWebhookProvider,
        "zapier_webhook" => Connectors::ZapierWebhookProvider,
        "make_webhook" => Connectors::MakeWebhookProvider,
        "n8n_webhook" => Connectors::N8nWebhookProvider,
        "gupshup" => Connectors::GupshupProvider,
        "plivo" => Connectors::PlivoProvider,
        "exotel" => Connectors::ExotelProvider,
        "kaleyra" => Connectors::KaleyraProvider,
        "sinch" => Connectors::SinchProvider,
        "cashfree" => Connectors::CashfreeProvider,
        "freshdesk" => Connectors::FreshdeskProvider,
        "intercom" => Connectors::IntercomProvider,
        "pipedrive" => Connectors::PipedriveProvider,
        "freshsales" => Connectors::FreshsalesProvider,
        "mailchimp" => Connectors::MailchimpProvider,
        "woocommerce" => Connectors::WoocommerceProvider,
        "typeform" => Connectors::TypeformProvider,
        "jotform" => Connectors::JotformProvider,
        # Commercial lane — wave 3 (ITSM, work management, CRM, marketing, email)
        "servicenow" => Connectors::ServicenowProvider,
        "jira" => Connectors::JiraProvider,
        "monday" => Connectors::MondayProvider,
        "asana" => Connectors::AsanaProvider,
        "clickup" => Connectors::ClickupProvider,
        "trello" => Connectors::TrelloProvider,
        "notion" => Connectors::NotionProvider,
        "airtable" => Connectors::AirtableProvider,
        "activecampaign" => Connectors::ActivecampaignProvider,
        "klaviyo" => Connectors::KlaviyoProvider,
        "mailgun" => Connectors::MailgunProvider
      }
    end

    def keys
      providers.keys
    end

    def key?(key)
      providers.key?(key.to_s)
    end

    def klass(key)
      providers[key.to_s]
    end

    def descriptor(key)
      klass(key)&.descriptor
    end

    def build(key, connector)
      providers.fetch(key.to_s).new(connector)
    end

    # For the admin "new connector" picker.
    def descriptors
      providers.values.map(&:descriptor)
    end

    # Anthropic tool-use specs for one connector's actions — the agent-facing
    # view of the same Provider::Action structs the admin UI lists. Names are
    # namespaced by connector id so several connectors of the same provider
    # never collide in a single tool set.
    def tool_specs(connector)
      klass(connector.provider)&.actions.to_a.map do |action|
        {
          name: "conn_#{connector.id}__#{action.key}",
          description: action.summary,
          input_schema: action.params || { "type" => "object", "properties" => {} }
        }
      end
    end
  end
end
