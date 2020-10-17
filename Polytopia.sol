contract Oracle {

    mapping (uint => mapping (uint => uint)) public points;
    mapping (uint => uint[]) public leaderboard;
    mapping (uint => mapping (uint => uint)) public leaderboardIndex;

    struct Score {
        uint start;
        uint end;
    }
    mapping (uint => mapping (uint => Score)) public segments;

    function _vote(uint _id, uint _t) internal {

        uint score = points[_t][_id];

        if(score == 0) {
            leaderboard[_t].push(_id);
            leaderboardIndex[_t][_id] = leaderboard[_t].length;
            if(segments[_t][1].end == 0) segments[_t][1].end = leaderboard[_t].length;
            segments[_t][1].start = leaderboard[_t].length;
        }
        else {
            uint index = leaderboardIndex[_t][_id];
            uint nextSegment = segments[_t][score].end;
            if(nextSegment != index) {
                leaderboardIndex[_t][_id] = nextSegment;
                leaderboardIndex[_t][leaderboard[_t][nextSegment-1]] = index;
                (leaderboard[_t][nextSegment - 1], leaderboard[_t][index - 1]) = (leaderboard[_t][index - 1], leaderboard[_t][nextSegment - 1]);
            }
            if(segments[_t][score].start == nextSegment) { 
                delete segments[_t][score].start; 
                delete segments[_t][score].end; 
            }
            else segments[_t][score].end++;
            if(segments[_t][score+1].end == 0) segments[_t][score+1].end = nextSegment;
            segments[_t][score+1].start = nextSegment;
        }
        points[_t][_id]++;
    }
}

contract Polytopia is Oracle {

    uint constant public period = 4 weeks;
    uint constant public genesis = 1604127600;

    uint constant public rngvote = 2 weeks;
    uint constant public randomize = 19 days;
    uint constant public premeet = 24 days;

    function schedule() public view returns (uint) { return genesis + ((block.timestamp - genesis) / period) * period; }

    mapping (uint => uint) public seed;
    mapping (uint => uint) public entropy;

    mapping (uint => uint) public hour;
    uint[24] public clockwork;
    uint public clock_nonce;

    function scheduleHour(uint _t) internal {
        if(clock_nonce == 0) clock_nonce = 24;
        uint _index = seed[_t] % clock_nonce;
        clock_nonce--;
        hour[_t] = clockwork[_index]*1 hours;
        clockwork[_index] = clockwork[clock_nonce];
        clockwork[clock_nonce] = clock_nonce;
    }

    enum Rank { Court, Pair }
    enum Registration { Commit, Vote, Complete }

    enum Token { Personhood, Registration, Immigration }

    struct Reg {
        Rank rank;
        uint id;
        bool verified;
    }
    mapping (uint => mapping (address => Reg)) public registry;
    mapping (uint => mapping (Rank => mapping (uint => address))) public registryIndex;
    mapping (uint => mapping (Rank => uint)) public registered;
    mapping (uint => uint) public shuffled;
    mapping (uint => mapping (address => Registration)) public registrationPhases;
    mapping (uint => mapping (Rank => mapping (uint => bool[2]))) public judgement;
    mapping (uint => mapping (uint => bool)) public disputed;

    mapping (uint => uint) public population;
    mapping (uint => mapping (address => uint)) public proofOfPersonhood;
    mapping (uint => mapping (uint => address)) public personhoodIndex;

    mapping (uint => mapping (Token => mapping (address => uint))) public balanceOf;
    mapping (uint => mapping (Token => mapping (address => mapping (address => uint)))) public allowed;

    function inState(uint _prev, uint _next, uint _t) internal view returns (bool) {
        if(_prev != 0) return (block.timestamp > _t + _prev);
        if(_next != 0) return (block.timestamp < _t + _next);
    }

    constructor() public {
        for(uint i; i<24; i++) clockwork[i] = i;
        uint t = schedule();
        balanceOf[t][Token.Registration][0xDb93d1a5e7A8D998FfAfd746471E4f3F3c8C1308] = 5;
        balanceOf[t][Token.Immigration][0xDb93d1a5e7A8D998FfAfd746471E4f3F3c8C1308] = 3;
        registered[t-period*2][Rank.Pair]++;
    }
    
    function initializeRandomization(uint _t) internal {
        entropy[_t] = seed[_t] = uint(registryIndex[_t][Rank.Pair][leaderboard[_t][0]]);
        scheduleHour(_t);
    }
    function _shuffle(uint _t) internal {
        if(shuffled[_t] == 0) initializeRandomization(_t);
        shuffled[_t]++;
        uint _shuffled = shuffled[_t];
        uint randomNumber = _shuffled + entropy[_t]%(registered[_t][Rank.Pair] + 1 - _shuffled);
        entropy[_t] = uint(keccak256(abi.encodePacked(entropy[_t], registryIndex[_t][Rank.Pair][randomNumber])));
        (registryIndex[_t][Rank.Pair][_shuffled], registryIndex[_t][Rank.Pair][randomNumber]) = (registryIndex[_t][Rank.Pair][randomNumber], registryIndex[_t][Rank.Pair][_shuffled]); 
        registry[_t][registryIndex[_t][Rank.Pair][_shuffled]].id = _shuffled;
    }
    function shuffle() external {
        uint t = schedule(); 
        require(inState(randomize, premeet, t));
        require(registrationPhases[t][msg.sender] == Registration.Vote);
        registrationPhases[t][msg.sender] = Registration.Complete;
        _shuffle(t);
    }
    function lateShuffle(uint _iterations) external { 
        uint t = schedule();
        require(inState(premeet, 0, t));
        for (uint i = 0; i < _iterations; i++) _shuffle(t); 
    }

    function register() external {
        uint t = schedule();
        require(inState(0, rngvote, t));
        require(registry[t][msg.sender].id == 0 && registry[t][msg.sender].rank != Rank.Pair);
        require(balanceOf[t][Token.Registration][msg.sender] >= 1);
        balanceOf[t][Token.Registration][msg.sender]--;
        registered[t][Rank.Pair]++;
        registryIndex[t][Rank.Pair][registered[t][Rank.Pair]] = msg.sender;
        registry[t][msg.sender].rank = Rank.Pair;
        balanceOf[t+period][Token.Immigration][msg.sender]++;
    }
    function immigrate() external {
        uint t = schedule();
        require(inState(0, rngvote, t));
        require(registry[t][msg.sender].id == 0 && registry[t][msg.sender].rank != Rank.Pair);
        require(balanceOf[t][Token.Immigration][msg.sender] >= 1);
        balanceOf[t][Token.Immigration][msg.sender]--;
        registered[t][Rank.Court]++;
        uint courts = registered[t][Rank.Court];
        registryIndex[t][Rank.Court][courts] = msg.sender;
        registry[t][msg.sender].id = courts;
        uint authorizeBorderToken = 1 + (courts - 1)%registered[t-period][Rank.Pair];
        balanceOf[t][Token.Immigration][registryIndex[t-period][Rank.Pair][authorizeBorderToken]]++;
    }
    
    function isVerified(Rank _rank, uint _unit, uint _t) public view returns (bool) {
        return (judgement[_t][_rank][_unit][0] == true && judgement[_t][_rank][_unit][1] == true);
    }

    function dispute(bool _premeet) external {
        uint t = schedule();
        if(_premeet != true) t -= period;
        require(registry[t][msg.sender].rank == Rank.Pair);
        uint id = registry[t][msg.sender].id;
        require(id != 0);
        uint pair = (id+1)/2;
        if(_premeet == false) require(!isVerified(Rank.Pair, pair, t));
        disputed[t][pair] = true;
    }
    function reassign(bool _premeet) external {
        uint t = schedule();
        if(_premeet != true) t -= period;
        uint id = registry[t][msg.sender].id;
        require(id != 0);
        uint countPairs = registered[t][Rank.Pair]/2;
        uint pair;
        if(registry[t][msg.sender].rank == Rank.Pair) {
            require(registrationPhases[t][msg.sender] == Registration.Complete);
            pair = (id + 1)/2;
            registry[t][msg.sender].rank = Rank.Court;
        }
        else pair = 1 + (id - 1)%countPairs;
        require(disputed[t][pair] == true);
        uint court = 1 + uint(keccak256(abi.encodePacked(msg.sender, pair)))%countPairs;
        while(registryIndex[t][Rank.Court][court] != address(0)) court += countPairs;
        registry[t][msg.sender].id = court;
        registryIndex[t][Rank.Court][court] = msg.sender;        
    }
    
    function completeVerification() external {
        uint t = schedule()-period;
        require(registry[t][msg.sender].verified == false);
        uint id = registry[t][msg.sender].id;
        uint pair;
        if(registry[t][msg.sender].rank == Rank.Court) {
            require(isVerified(Rank.Court, id, t));
            pair = 1 + (id - 1)%(registered[t][Rank.Pair]/2);
        }
        else pair = (id + 1) /2;
        require(isVerified(Rank.Pair, pair, t));
        balanceOf[t+period][Token.Personhood][msg.sender]++;
        balanceOf[t+period][Token.Registration][msg.sender]++;
        registry[t][msg.sender].verified = true;
    }
    function _verify(address _account, address _signer, uint _t) internal {
        require(inState(hour[_t], 0, _t));
        require(_account != _signer);
        uint id = registry[_t][_account].id;
        require(id != 0);
        uint peer = registry[_t][_signer].id;
        require(registry[_t][_signer].rank == Rank.Pair);
        require(registrationPhases[_t][_signer] == Registration.Complete);
        require(peer != 0);
        Rank rank = registry[_t][_account].rank;
        uint unit;
        uint pair;
        if(rank == Rank.Pair) {
            pair = (id + 1)/2;
            unit = pair;
        }
        else {
            unit = id;
            pair = 1 + (unit - 1)%(registered[_t][Rank.Pair]/2);
        }
        require(disputed[_t][pair] == false);
        require(pair == (peer+1)/2);
        judgement[_t][rank][unit][peer%2] = true;
    }
    function verify(address _account) external { _verify(_account, msg.sender, schedule()-period); }

    function msgHash(uint _t) internal view returns (bytes32) { return keccak256(abi.encodePacked(msg.sender, _t)); }

    function uploadSignature(bytes32 r, bytes32 s, uint8 v) external {
        uint t = schedule()-period; _verify(msg.sender, ecrecover(msgHash(t), v, r, s), t);
    }
    function courtSignature(bytes32[2] calldata r, bytes32[2] calldata s, uint8[2] calldata v) external {
        uint t = schedule()-period; bytes32 _msgHash = msgHash(t);
        _verify(msg.sender, ecrecover(_msgHash, v[0], r[0], s[0]), t);
        _verify(msg.sender, ecrecover(_msgHash, v[1], r[1], s[1]), t);
    }
    
    function claimPersonhood() external {
        uint t = schedule();
        require(proofOfPersonhood[t][msg.sender] == 0 && balanceOf[t][Token.Personhood][msg.sender] >= 1);
        balanceOf[t][Token.Personhood][msg.sender]--;
        population[t]++;
        proofOfPersonhood[t][msg.sender] = population[t];
        personhoodIndex[t][population[t]] = msg.sender;
    }
    
    function _transfer(uint _t, address _from, address _to, uint _value, Token _token) internal { 
        require(balanceOf[_t][_token][_from] >= _value);
        balanceOf[_t][_token][_from] -= _value;
        balanceOf[_t][_token][_to] += _value;        
    }
    function transfer(address _to, uint _value, Token _token) external {
        _transfer(schedule(), msg.sender, _to, _value, _token);
    }
    function approve(address _spender, uint _value, Token _token) external {
        allowed[schedule()][_token][msg.sender][_spender] = _value;
    }
    function transferFrom(address _from, address _to, uint _value, Token _token) external {
        uint t = schedule();
        require(allowed[t][_token][_from][msg.sender] >= _value);
        _transfer(t, _from, _to, _value, _token);
        allowed[t][_token][_from][msg.sender] -= _value;
    }
    
    function vote(uint _id) external {
        uint t = schedule(); 
        require(inState(rngvote, randomize, t)); 
        require(registry[t][msg.sender].rank == Rank.Pair);
        require(registrationPhases[t][msg.sender] == Registration.Commit);
        registrationPhases[t][msg.sender] = Registration.Vote;
        require(_id != 0 && _id <= registered[t][Rank.Pair]);
        _vote(_id, t);
    }
}
