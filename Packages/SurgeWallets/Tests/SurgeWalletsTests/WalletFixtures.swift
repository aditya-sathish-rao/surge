import Foundation

enum WalletFixtures {
    /// Documented shape of `GET https://api.deepseek.com/user/balance`.
    static let deepSeekBalance = """
        {
          "is_available": true,
          "balance_infos": [
            {
              "currency": "USD",
              "total_balance": "12.40",
              "granted_balance": "0.00",
              "topped_up_balance": "12.40"
            }
          ]
        }
        """

    static let deepSeekNoBalance = """
        {
          "is_available": false,
          "balance_infos": []
        }
        """

    /// Documented shape of `GET https://openrouter.ai/api/v1/auth/key` with a spend limit.
    static let openRouterKey = """
        {
          "data": {
            "label": "surge-key",
            "usage": 1.50,
            "limit": 10.0,
            "is_free_tier": false,
            "rate_limit": { "requests": 1, "interval": "10s" }
          }
        }
        """

    static let openRouterKeyWithoutLimit = """
        {
          "data": {
            "label": "surge-key",
            "usage": 4.25,
            "limit": null,
            "is_free_tier": false
          }
        }
        """

    static let unauthorized = """
        { "error": { "message": "invalid api key" } }
        """

    static let malformed = """
        { "is_available": tru
        """
}

extension WalletFixtures {
    /// Documented shape of `GET https://api.deepseek.com/models`.
    static let deepSeekModels = """
        {
          "object": "list",
          "data": [
            {
              "id": "deepseek-chat",
              "object": "model",
              "owned_by": "deepseek",
              "context_window": 1048576,
              "max_output_tokens": 8192
            },
            {
              "id": "deepseek-reasoner",
              "object": "model",
              "owned_by": "deepseek",
              "context_window": 1048576,
              "max_output_tokens": 65536
            }
          ]
        }
        """

    /// A trimmed `GET https://openrouter.ai/api/v1/models` with per-token pricing strings.
    static let openRouterModels = """
        {
          "data": [
            {
              "id": "anthropic/claude-3.5-sonnet",
              "context_length": 200000,
              "pricing": {
                "prompt": "0.000003",
                "completion": "0.000015",
                "input_cache_read": "0.0000003"
              },
              "top_provider": { "max_completion_tokens": 8192 }
            },
            {
              "id": "deepseek/deepseek-chat",
              "context_length": 1048576,
              "pricing": {
                "prompt": "0.00000027",
                "completion": "0.0000011"
              }
            }
          ]
        }
        """

    /// OpenRouter quotes -1 for models whose price varies, which is not a number Surge can price.
    static let openRouterModelsVariablePricing = """
        {
          "data": [
            {
              "id": "openrouter/auto",
              "context_length": 2000000,
              "pricing": { "prompt": "-1", "completion": "-1" }
            }
          ]
        }
        """

    /// A model list missing the context window is not usable and must be dropped.
    static let openRouterModelsMissingWindow = """
        {
          "data": [
            { "id": "broken", "pricing": { "prompt": "0.000001", "completion": "0.000002" } }
          ]
        }
        """
}
