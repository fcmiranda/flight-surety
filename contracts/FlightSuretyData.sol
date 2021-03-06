pragma solidity 0.8.9;

contract FlightSuretyData {
    /********************************************************************************************/
    /*                                       DATA VARIABLES                                     */
    /********************************************************************************************/

    uint8 private constant STS_CODE_UNKNOWN = 0;
    uint8 private constant STS_CODE_ON_TIME = 10;
    uint8 private constant STS_CODE_LATE_AIRLINE = 20;
    uint8 private constant STS_CODE_LATE_WEATHER = 30;
    uint8 private constant STS_CODE_LATE_TECHNICAL = 40;
    uint8 private constant STS_CODE_LATE_OTHER = 50;

    address private contractOwner;

    uint256 private enabled = block.timestamp;
    uint256 private counter = 1;

    bool private operational = true;

    mapping(address => uint256) private authorizedContracts;

    struct Insurance {
        address passenger;
        uint256 amount;
        uint256 multiplier;
        bool isCredited;
    }

    struct Airline {
        string name;
        bool isFunded;
        bool isRegistered;
    }

    struct Flight {
        bool isRegistered;
        uint8 statusCode;
        uint256 updatedTimestamp;
        address airline;
        string flight;
        string from;
        string to;
    }
    mapping(bytes32 => Flight) private flights;
    bytes32[] registeredFlights = new bytes32[](0);

    address[] multiConsensusList = new address[](0);

    mapping(address => uint256) public pending;
    mapping(address => Airline) private airlines;
    mapping(bytes32 => Insurance[]) passengersWithInsurancePerFlight;

    address[] listOfRegisteredAirlines = new address[](0);

    /********************************************************************************************/
    /*                                       CONSTRUCTOR                                        */
    /********************************************************************************************/

    constructor(string memory firstAirlineName, address firstAirlineAddress)
        public
    {
        contractOwner = msg.sender;

        airlines[firstAirlineAddress] = Airline({
            name: firstAirlineName,
            isFunded: false,
            isRegistered: true
        });

        listOfRegisteredAirlines.push(firstAirlineAddress);
    }

    /********************************************************************************************/
    /*                                       FUNCTION MODIFIERS                                 */
    /********************************************************************************************/

    // Modifiers help avoid duplication of code. They are typically used to validate something
    // before a function is allowed to be executed.

    /**
     * @dev Modifier that requires the "operational" boolean variable to be "true"
     *      This is used on all state changing functions to pause the contract in
     *      the event there is an issue that needs to be fixed
     */
    modifier requireIsOperational() {
        require(isOperational(), "Contract is currently not operational");
        _; // All modifiers require an "_" which indicates where the function body will be added
    }

    /**
     * @dev Modifier that requires the "ContractOwner" account to be the function caller
     */
    modifier requireContractOwner() {
        require(msg.sender == contractOwner, "Caller is not contract owner");
        _;
    }

    /**
     * @dev Modifier that requires function caller to be authorized
     */
    modifier requireIsCallerAuthorized() {
        require(
            authorizedContracts[msg.sender] == 1,
            "Caller is not authorized"
        );
        _;
    }

    /**
     * @dev Modifier that requires address to be valid
     */
    modifier requireValidAddress(address addr) {
        require(addr != address(0), "Invalid address");
        _;
    }

    /**
     * @dev Limit rate of withdrawals
     */
    modifier rateLimit(uint256 time) {
        require(block.timestamp >= enabled, "Rate limiting in effect");
        _;
    }

    /**
     * @dev Prevent re-entrancy bugs for withdrawals
     */
    modifier entrancyGuard() {
        uint256 guard = counter;
        _;
        require(guard == counter, "permission denied");
    }

    /********************************************************************************************/
    /*                                       EVENT DEFINITIONS                                  */
    /********************************************************************************************/

    event FlightRegistered(
        bytes32 flightKey,
        address airline,
        string flight,
        string from,
        string to,
        uint256 timestamp
    );
    event FlightStatusUpdated(
        address airline,
        string flight,
        uint256 timestamp,
        uint8 statusCode
    );
    event InsuranceBought(
        address airline,
        string flight,
        uint256 timestamp,
        address passenger,
        uint256 amount,
        uint256 multiplier
    );
    event AirlineRegistered(string name, address addr);
    event AirlineFunded(string name, address addr);
    event InsureeCredited(address passenger, uint256 amount);
    event AccountWithdrawn(address passenger, uint256 amount);

    /********************************************************************************************/
    /*                                       UTILITY FUNCTIONS                                  */
    /********************************************************************************************/

    /**
     * @dev Get operating status of contract
     *
     * @return A bool that is the current operating status
     */
    function isOperational() public view returns (bool) {
        return operational;
    }

    /**
     * @dev Get airline details
     *
     * @return Airline with the provided address
     */
    function getAirlineName(address airline)
        external
        view
        returns (string memory)
    {
        return airlines[airline].name;
    }

    /**
     * @dev Check if the address is a registered airline
     *
     * @return A bool confirming whether or not the address is a registered airline
     */
    function isAirline(address airline) external view returns (bool) {
        return airlines[airline].isRegistered;
    }

    /**
     * @dev Check if the address is a funded airline
     *
     * @return A bool confirming whether or not the address is a funded airline
     */
    function isFundedAirline(address airline) external view returns (bool) {
        return airlines[airline].isFunded;
    }

    /**
     * @dev Get registered airlines
     *
     * @return An array with the addresses of all registered airlines
     */
    function getRegisteredAirlines() external view returns (address[] memory) {
        return listOfRegisteredAirlines;
    }

    /**
     * @dev Check if the flight is registered
     */
    function getFlightStatusCode(
        address airline,
        string calldata flight,
        uint256 timestamp
    ) external view returns (uint8) {
        return flights[getFlightKey(airline, flight, timestamp)].statusCode;
    }

    /**
     * @dev Check if the flight is registered
     */
    function isFlight(
        address airline,
        string calldata flight,
        uint256 timestamp
    ) external view returns (bool) {
        return flights[getFlightKey(airline, flight, timestamp)].isRegistered;
    }

    /**
     * @dev Check if the flight status code is "landed"
     */
    function isLandedFlight(
        address airline,
        string calldata flight,
        uint256 timestamp
    ) external view returns (bool) {
        return
            flights[getFlightKey(airline, flight, timestamp)].statusCode >
            STS_CODE_UNKNOWN;
    }

    /**
     * @dev Check if the passenger is registerd for the flight
     */
    function isInsured(
        address passenger,
        address airline,
        string calldata flight,
        uint256 timestamp
    ) external view returns (bool) {
        Insurance[] memory insuredPassengers = passengersWithInsurancePerFlight[
            getFlightKey(airline, flight, timestamp)
        ];

        for (uint256 i = 0; i < insuredPassengers.length; i++) {
            if (insuredPassengers[i].passenger == passenger) {
                return true;
            }
        }
        return false;
    }

    /**
     * @dev Sets contract operations on/off
     *
     * When operational mode is disabled, all write transactions except for this one will fail
     */
    function setOperatingStatus(bool mode) external requireContractOwner {
        bool isDuplicateCall = false;

        for (uint256 i = 0; i < multiConsensusList.length; i++) {
            if (multiConsensusList[i] == msg.sender) {
                isDuplicateCall = true;
                break;
            }
        }

        require(isDuplicateCall == false, "Duplicate");

        multiConsensusList.push(msg.sender);

        if (multiConsensusList.length >= 1) {
            operational = mode;
            multiConsensusList = new address[](0);
        }
    }

    function getPendingPaymentAmount(address passenger)
        external
        view
        returns (uint256)
    {
        return pending[passenger];
    }

    function deauthorizeCaller(address contractAddress)
        external
        requireContractOwner
    {
        delete authorizedContracts[contractAddress];
    }

    function authorizeCaller(address contractAddress)
        external
        requireContractOwner
    {
        authorizedContracts[contractAddress] = 1;
    }

    /********************************************************************************************/
    /*                                     SMART CONTRACT FUNCTIONS                             */
    /********************************************************************************************/

    function registerAirline(string calldata name, address addr)
        external
        requireIsOperational
        returns (bool success)
    {
        require(
            !airlines[addr].isRegistered,
            "The flight has registered already"
        );

        airlines[addr] = Airline({
            name: name,
            isFunded: false,
            isRegistered: true
        });

        listOfRegisteredAirlines.push(addr);

        emit AirlineRegistered(name, addr);

        return true;
    }

    function fundAirline(address addr)
        external
        requireIsOperational
        requireIsCallerAuthorized
    {
        require(airlines[addr].isFunded, "This airline has funded already");
        airlines[addr].isFunded = true;
        emit AirlineFunded(airlines[addr].name, addr);
    }

    /**
     * @dev Process flights
     */
    function processFlightStatus(
        address airline,
        string calldata flight,
        uint256 timestamp,
        uint8 statusCode
    ) external requireIsOperational {
        bytes32 key = getFlightKey(airline, flight, timestamp);
        if (flights[key].statusCode == STS_CODE_UNKNOWN) {
            flights[key].statusCode = statusCode;
            if (statusCode == STS_CODE_LATE_AIRLINE) {
                creditInsurees(airline, flight, timestamp);
            }
        }

        emit FlightStatusUpdated(airline, flight, timestamp, statusCode);
    }

    /**
     * @dev Credits payouts to insurees
     */
    function creditInsurees(
        address airline,
        string memory flight,
        uint256 timestamp
    ) internal requireIsOperational {
        bytes32 flightKey = getFlightKey(airline, flight, timestamp);

        for (
            uint256 i = 0;
            i < passengersWithInsurancePerFlight[flightKey].length;
            i++
        ) {
            Insurance memory insurance = passengersWithInsurancePerFlight[
                flightKey
            ][i];
            if (insurance.isCredited == false) {
                uint256 amount = insurance.amount;
                pending[insurance.passenger] += amount;
                insurance.isCredited = true;
                emit InsureeCredited(insurance.passenger, amount);
            }
        }
    }

    /**
     * @dev Register a flight
     */
    function registerFlight(
        address airline,
        string calldata flight,
        string calldata from,
        string calldata to,
        uint256 timestamp
    )
        external
        requireIsOperational
        requireIsCallerAuthorized
        requireValidAddress(airline)
    {
        bytes32 key = getFlightKey(airline, flight, timestamp);
        require(!flights[key].isRegistered, "Flight has registered already");

        flights[key] = Flight({
            statusCode: STS_CODE_UNKNOWN,
            isRegistered: true,
            airline: airline,
            flight: flight,
            from: from,
            to: to,
            updatedTimestamp: timestamp
        });

        registeredFlights.push(key);

        emit FlightRegistered(key, airline, flight, from, to, timestamp);
    }

    function buy(
        address airline,
        string calldata flight,
        uint256 timestamp,
        address passenger,
        uint256 amount,
        uint256 multiplier
    ) external requireIsOperational requireIsCallerAuthorized {
        bytes32 key = getFlightKey(airline, flight, timestamp);
        passengersWithInsurancePerFlight[key].push(
            Insurance({
                passenger: passenger,
                amount: amount,
                isCredited: false,
                multiplier: multiplier
            })
        );

        emit InsuranceBought(
            airline,
            flight,
            timestamp,
            passenger,
            amount,
            multiplier
        );
    }

    /**
     * @dev Transfers eligible payout funds to insuree
     */
    function pay(address passenger)
        external
        requireIsOperational
        requireIsCallerAuthorized
    {
        require(passenger == tx.origin, "Contracts not allowed");
        require(pending[passenger] > 0, "Funds unavailable for passenger");

        uint256 amount = pending[passenger];
        pending[passenger] = 0;
        address payable passengerAddr = payable(passenger);

        passengerAddr.transfer(amount);

        emit AccountWithdrawn(passenger, amount);
    }

    /**
     * @dev Initial funding for the insurance. Unless there are too many delayed flights
     *      resulting in insurance payouts, the contract should be self-sustaining
     */
    function fund() public payable requireIsOperational {}

    function getFlightKey(
        address airline,
        string memory flight,
        uint256 timestamp
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(airline, flight, timestamp));
    }

    /**
     * @dev Fallback function for funding smart contract.
     */
    receive() external payable {
        fund();
    }
}
