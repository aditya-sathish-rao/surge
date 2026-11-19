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
