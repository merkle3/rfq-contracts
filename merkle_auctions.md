```mermaid
sequenceDiagram
    actor Maker
    participant Merkle Auction Settler SC
    participant Merkle RFQ API
    participant Order Matching Engine
    participant Merkle PostgresDB
    actor Taker

    Note over Maker: Maker wants as much USDT for 100 USDC

    Maker -->> Merkle Auction Settler SC: Approves SC to pull funds
    Maker -->> Merkle RFQ API: Creates an order via HTTP POST /order
    Merkle RFQ API -->> Merkle PostgresDB: Db order creation
    Taker -->>  Merkle RFQ API: Receives the order via WS stream or HTTP GET /orders
    Taker -->> Merkle RFQ API: Bids on the order via POST /bid
    Merkle RFQ API -->> Merkle Auction Settler SC: Validation pre transaction via eth_call
    Merkle RFQ API -->> Merkle PostgresDB: Db Bid creation
    Order Matching Engine -->> Merkle PostgresDB: Finds the Bid, matches it and changes status
    Order Matching Engine -->> Merkle Auction Settler SC: Creates transaction
    Merkle Auction Settler SC -->> Maker: Pulls tokenIn amount out
    Merkle Auction Settler SC -->> Taker: Transfer tokenIn amount
    Taker -->> Merkle Auction Settler SC: Transfers tokenOut amount + eth gas via callback execution
    Order Matching Engine -->> Merkle PostgresDB: Updates Bid status and order status

```
