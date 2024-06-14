module food_share::food_share {

    use sui::transfer;
    use sui::clock::{Self, Clock};
    use sui::object::{Self, UID, ID};
    use sui::tx_context::{Self, TxContext};
    use sui::table::{Self, Table};
    use std::option::{Option, none, some, is_some, contains, borrow};

    const EInvalidPost: u64 = 1;
    const ENotDonor: u64 = 4;
    const ENotDriver: u64 = 5;
    const ENotReceiver: u64 = 6;
    const ERROR_INVALID_CAP :u64 = 7;
    const EInvalidAssignment: u64 = 8;

    struct SurplusPost has key, store {
        id: UID,
        donor: address,
        donorName: vector<u8>,
        foodType: vector<u8>,
        quantity: u64,
        bestBefore: u64,
        handlingInstructions: vector<u8>,
        receiver: Option<address>,
        driver: Option<address>,
        created_at: u64,
        dispute: bool,
        delivered: bool,
        paid: bool,
    }

    struct DonorProfile has key, store {
        id: UID,
        donor: address,
        donorName: vector<u8>,
        donorType: vector<u8>,
    }

    struct ReceiverProfile has key, store {
        id: UID,
        receiver: address,
        receiverName: vector<u8>,
        needs: vector<u8>,
        capacity: u64,
        receivingTimes: vector<u8>,
    }

    struct ReceiverCap has key {
        id: UID,
        receiverId: ID
    }

    struct DriverProfile has key, store {
        id: UID,
        driver: address,
        driverName: vector<u8>,
        vehicleType: vector<u8>,
        driverRating: u64,
    }

    struct SurplusRecord has key, store {
        id: UID,
        donor: address,
        receiver: address,
        proof_of_delivery: vector<u8>,
    }

    struct Assignment has key, store {
        id: UID,
        post: ID,
        driver: ID,
        receiver: ID,
        wages: u64,
        pickupLocation: vector<u8>,
        deliveryLocation: vector<u8>,
    }

    struct SurplusRecords has key, store {
        id: UID,
        completedDeliveries: Table<ID, SurplusRecord>,
    }

    /// Function to create a new Donor profile
    public entry fun create_donor_profile(
        donor: address, donorName: vector<u8>, donorType: vector<u8>, ctx: &mut TxContext
    ) {
        let donor_id = object::new(ctx);
        transfer::share_object(DonorProfile {
            id: donor_id,
            donor: donor,
            donorName: donorName,
            donorType: donorType,
        });
    }

    /// Function to create a new Receiver profile
    public entry fun create_receiver_profile(
        receiver: address, receiverName: vector<u8>, needs: vector<u8>, capacity: u64, 
        receivingTimes: vector<u8>, ctx: &mut TxContext
    ) {
        let receiver_id = object::new(ctx);
        transfer::share_object(ReceiverProfile {
            id: receiver_id,
            receiver: receiver,
            receiverName: receiverName,
            needs: needs,
            capacity: capacity,
            receivingTimes: receivingTimes,
        });
    }

    /// Function to create a new driver profile
    public entry fun create_driver_profile(
        driver: address, driverName: vector<u8>, vehicleType: vector<u8>, ctx: &mut TxContext
    ) {
        let driver_id = object::new(ctx);
        transfer::share_object(DriverProfile {
            id: driver_id,
            driver: driver,
            driverName: driverName,
            vehicleType: vehicleType,
            driverRating: 0,
        });
    }

    /// Function to create a new surplus post
    public entry fun create_surplus_post(
        donor: address, donorName: vector<u8>, foodType: vector<u8>, 
        quantity: u64, bestBefore: u64, handlingInstructions: vector<u8>,
        clock: &Clock, ctx: &mut TxContext
    ) {
        let post_id = object::new(ctx);
        transfer::share_object(SurplusPost {
            id: post_id,
            donor: donor,
            donorName: donorName,
            foodType: foodType,
            quantity: quantity,
            bestBefore: bestBefore,
            handlingInstructions: handlingInstructions,
            receiver: none(),
            driver: none(),
            created_at: clock::timestamp_ms(clock),
            dispute: false,
            delivered: false,
            paid: false,
        });
    }

    /// After the Donor posts a surplus, the receiver can claim the surplus
    public entry fun claim_surplus_post(post: &mut SurplusPost, receiver: address, ctx: &mut TxContext) {
        assert!(tx_context::sender(ctx) == receiver, ENotReceiver);
        assert!(post.receiver == none(), EInvalidPost);
        post.receiver = some(receiver);
    }

    /// After the receiver claims the surplus, they can create an assignment for the driver
    public entry fun create_assignment(
        cap: &ReceiverCap, post: &mut SurplusPost, driver: DriverProfile, 
        wages: u64, pickupLocation: vector<u8>, deliveryLocation: vector<u8>, ctx: &mut TxContext
    ) {
        assert!(cap.receiverId == object::id(&post), ERROR_INVALID_CAP);
        assert!(post.receiver != none(), EInvalidPost);
        assert!(tx_context::sender(ctx) == *borrow(&post.receiver), ENotReceiver);

        let assignment_id = object::new(ctx);
        transfer::share_object(Assignment {
            id: assignment_id,
            post: object::id(post),
            driver: driver.id,
            receiver: cap.receiverId,
            wages: wages,
            pickupLocation: pickupLocation,
            deliveryLocation: deliveryLocation,
        });
    }

    /// After the receiver creates an assignment, the driver can accept the delivery
    public entry fun accept_delivery(post: &mut SurplusPost, driver: address, ctx: &mut TxContext) {
        assert!(is_some(&post.receiver), EInvalidAssignment);
        assert!(tx_context::sender(ctx) == driver, ENotDriver);
        post.driver = some(driver);
        post.delivered = true;
    }

    /// After the driver completes the delivery, they can mark it as delivered
    public entry fun mark_as_delivered(
        post: &mut SurplusPost, records: &mut SurplusRecords, proof: vector<u8>, ctx: &mut TxContext
    ) {
        assert!(contains(&post.driver, &tx_context::sender(ctx)), ENotDriver);

        let surplusRecord = SurplusRecord {
            id: object::new(ctx),
            donor: post.donor,
            receiver: *borrow(&post.receiver),
            proof_of_delivery: proof,
        };
        table::add<ID, SurplusRecord>(&mut records.completedDeliveries, object::uid_to_inner(&post.id), surplusRecord);
    }

    /// After the driver has delivered the surplus, the receiver can report issues in case of any problem
    public entry fun report_issues(post: &mut SurplusPost, ctx: &mut TxContext) {
        assert!(contains(&post.receiver, &tx_context::sender(ctx)), ENotReceiver);
        post.dispute = true;
    }

    /// The Donor resolves any issues reported with the surplus post
    public entry fun resolve_issues(post: &mut SurplusPost, ctx: &mut TxContext) {
        assert!(tx_context::sender(ctx) == post.donor, ENotDonor);
        assert!(is_some(&post.receiver), EInvalidPost);
        post.dispute = false;
    }

    /// The Donor can extend the best before date of the surplus post
    public entry fun extend_best_before(post: &mut SurplusPost, new_best_before: u64, ctx: &mut TxContext) {
        assert!(tx_context::sender(ctx) == post.donor, ENotDonor);
        post.bestBefore = new_best_before;
    }

    /// The Donor can update the quantity of the surplus post
    public entry fun update_quantity(post: &mut SurplusPost, new_quantity: u64, ctx: &mut TxContext) {
        assert!(tx_context::sender(ctx) == post.donor, ENotDonor);
        post.quantity = new_quantity;
    }

    /// The Receiver can rate the Driver
    public entry fun rate_driver(
        driver: &mut DriverProfile, rating: u64, receiver: address, ctx: &mut TxContext
    ) {
        assert!(tx_context::sender(ctx) == receiver, ENotReceiver);
        driver.driverRating = driver.driverRating + rating;
    }

    /// Function to remove a surplus post (cleanup function)
    public entry fun remove_surplus_post(post: SurplusPost, ctx: &mut TxContext) {
        assert!(tx_context::sender(ctx) == post.donor, ENotDonor);
        // Implementation for removing the surplus post object
        transfer::delete_object(post);
    }
}
