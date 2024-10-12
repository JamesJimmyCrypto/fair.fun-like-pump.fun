module fair_fun::order {

    use std::string::String;
    use fair_fun::prebuyer::{Self, Prebuyer};
    use sui::clock::Clock;
    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Balance};
    use sui::sui::SUI;

    const MIN_POOL_LIFETIME: u64 = 1800000;
    const ENoUser: u64 = 0;
    const ONLY_WITHDRAW_DURATION: u64 = 3 * 60 * 1000;  // 3 minutes

    public enum OrderStatus has store, drop, copy {
        //Init,
        Open,
        OnlyWithdraw,
        OnDistribution,
        //Cancelled,
        //Finished,
    }
    
    public struct Metadata has store {
        name: String,
        description: String,
        image_url: String,
        social_urls: vector<String>
    }

    public struct Order has key {
        id: UID,
        metadata: Metadata,
        created_at: u64,
        release_date: u64,
        status: OrderStatus,
        prebuyers: vector<Prebuyer>
    }    

    // Admin capability
    public struct AdminCap has key {
        id: UID,
    }

    // Create new Order object
    public fun new(metadata: Metadata, release_date: u64, clock: &Clock, ctx: &mut TxContext) {

        // Get current time
        let current_time = clock.timestamp_ms();

        // Abort if release_date is too close
        assert!(release_date > current_time + MIN_POOL_LIFETIME, 0);    //TODO errors 

        let order = Order {
            id: object::new(ctx),
            metadata: metadata,
            created_at: clock.timestamp_ms(),
            release_date: release_date,
            status: OrderStatus::Open,
            prebuyers: vector::empty<Prebuyer>()
        };

        transfer::share_object(order);
    }

    fun update_status(order: &mut Order, clock: &Clock) {

        let current_time = clock.timestamp_ms();

        // If status is Open
        if (order.status == OrderStatus::Open) {
            // Withdrawal time
            let only_withdraw_start = order.release_date - ONLY_WITHDRAW_DURATION;

            // If current time is past withdrawal start
            if (current_time >= only_withdraw_start) {
                // Set to OnlyWithdraw
                order.status = OrderStatus::OnlyWithdraw;
            }
        };

        // If status is OnlyWithdraw
        if (order.status == OrderStatus::OnlyWithdraw) {
            // If current time is past release_date
            if (current_time >= order.release_date) {
                // Set to OnDistribution
                order.status = OrderStatus::OnDistribution;
            }
        }

    }

    fun add_buyer(
        bid: Coin<SUI>, 
        sui: Coin<SUI>, 
        order: &mut Order, 
        clock: &Clock,
        ctx: &mut TxContext) {

        let bid_as_balance = coin::into_balance(bid);
        let sui_as_balance = coin::into_balance(sui);

        let prebuyer = prebuyer::new(sui_as_balance, bid_as_balance, clock, &order.release_date, ctx);

        // Save the prebuyer in the vector
        vector::push_back<Prebuyer>(&mut order.prebuyers, prebuyer);
    }

    fun update_buyer(
        bid: Coin<SUI>,
        sui: Coin<SUI>,
        release_date: &u64,
        prebuyer: &mut Prebuyer,
        clock: &Clock,
        ctx: &TxContext) {

        assert!(bid.value() > 0);
        assert!(sui.value() > 0);

        let bid_as_balance = coin::into_balance(bid);
        let sui_as_balance = coin::into_balance(sui);

        prebuyer.update(sui_as_balance, bid_as_balance, clock, release_date);
        }

    public fun add_or_update_buyer(order: &mut Order, bid: Coin<SUI>, sui: Coin<SUI>, clock: &Clock, ctx: &mut TxContext) {

        order.update_status(clock);

        // Order should be open to bids
        assert!(order.status == OrderStatus::Open);

        let mut i = 0;
        while (i <= order.prebuyers.length()) {
            let prebuyer = order.prebuyers.borrow_mut(i);
            if (prebuyer.get_bidder_address() == ctx.sender()) {
                update_buyer(bid, sui, &order.release_date, prebuyer, clock, ctx);
                return
            };
            i = i + 1;
        };

        add_buyer(bid, sui, order, clock, ctx);
    }

    public fun permanent_exit(order: &mut Order, ctx: &mut TxContext): Coin<SUI> {

        assert!(order.status == OrderStatus::Open || order.status == OrderStatus::OnlyWithdraw);

        let mut i = 0;
        while (i <= order.prebuyers.length()) {
            let prebuyer = order.prebuyers.borrow_mut(i);
            if (prebuyer.get_bidder_address() == ctx.sender()) {
                let (mut lockings, bid_amount) = prebuyer.exit_bidder();
                balance::join(&mut lockings, bid_amount);
                let withdraw_amount: Coin<SUI> = coin::from_balance(lockings, ctx);
                return withdraw_amount
            };
            i = i + 1;
        };
        abort ENoUser
    }
}