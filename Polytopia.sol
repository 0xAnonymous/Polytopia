contract Polytopia {

    uint constant public period = 4 weeks;
    uint constant public genesis = 1601708400;

    uint constant public rngvote = 2 weeks;
    uint constant public randomize = 3 weeks;

    function schedule() public view returns (uint) { return genesis + ((block.timestamp - genesis) / period) * period; }
    function t(int _periods) public view returns (uint) { return schedule() + uint(_periods)*period; }

    mapping (uint => uint) public seed;
    mapping (uint => uint) public entropy;

    mapping (uint => uint) public hour;
    uint[] public clockwork;
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
    enum Registration { None, Commit, Vote, Complete }
    
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

    mapping (uint => mapping (uint => uint)) public points;
    mapping (uint => uint[]) public leaderboard;
    mapping (uint => mapping (uint => uint)) public leaderboardIndex;

    struct Score {
        uint start;
        uint end;
    }
    mapping (uint => mapping (uint => Score)) public segments;
    
    function inState(uint _prev, uint _next, uint _t) internal view returns (bool) {
        if(_prev != 0) return (block.timestamp > _t + _prev);
        if(_next != 0) return (block.timestamp < _t + _next);
    }

    constructor() public {
        for(uint i; i<24; i++) clockwork.push(i);
        uint _t = schedule();
        balanceOf[_t][Token.Registration][0xDb93d1a5e7A8D998FfAfd746471E4f3F3c8C1308] = 4;
        balanceOf[_t][Token.Immigration][0xDb93d1a5e7A8D998FfAfd746471E4f3F3c8C1308] = 4;
        balanceOf[_t+period][Token.Registration][0xDb93d1a5e7A8D998FfAfd746471E4f3F3c8C1308] = 4;
        balanceOf[_t+period][Token.Immigration][0xDb93d1a5e7A8D998FfAfd746471E4f3F3c8C1308] = 4;        
        
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
        uint _t = schedule(); 
        require(inState(randomize, 0, _t));
        require(registrationPhases[_t][msg.sender] == Registration.Vote);
        registrationPhases[_t][msg.sender] = Registration.Complete;
        _shuffle(_t);
    }
    function lateShuffle(uint _iterations) external { for (uint i = 0; i < _iterations; i++) _shuffle(t(-1)); }

    function register() external {
        uint _t = schedule();
        require(inState(0, rngvote, _t));
        require(registry[_t][msg.sender].id == 0 && registry[_t][msg.sender].rank != Rank.Pair);
        require(balanceOf[_t][Token.Registration][msg.sender] >= 1);
        balanceOf[_t][Token.Registration][msg.sender]--;
        registered[_t][Rank.Pair]++;
        registryIndex[_t][Rank.Pair][registered[_t][Rank.Pair]] = msg.sender;
        registry[_t][msg.sender].rank = Rank.Pair;
        registrationPhases[_t][msg.sender] = Registration.Commit;
        balanceOf[_t+period*2][Token.Immigration][msg.sender]++;
    }
    function immigrate() external {
        uint _t = schedule();
        require(inState(0, rngvote, _t));
        require(registry[_t][msg.sender].id == 0 && registry[_t][msg.sender].rank != Rank.Pair);
        require(balanceOf[_t][Token.Immigration][msg.sender] >= 1);
        balanceOf[_t][Token.Immigration][msg.sender]--;
        registered[_t][Rank.Court]++;
        uint courts = registered[_t][Rank.Court];
        registryIndex[_t][Rank.Court][courts] = msg.sender;
        registry[_t][msg.sender].id = courts;
        balanceOf[_t][Token.Immigration][registryIndex[_t-period*2][Rank.Pair][courts%registered[_t-period*2][Rank.Pair]]]++;
    }
    
    function isVerified(Rank _rank, uint _unit, uint _t) public view returns (bool) {
        return (judgement[_t][_rank][_unit][0] == true && judgement[_t][_rank][_unit][1] == true);
    }

    function dispute(bool _premeet) external {
        uint _t; if(_premeet == true) _t = t(-1); else _t = t(-2);
        uint id = registry[_t][msg.sender].id;
        require(id != 0);
        require(registry[_t][msg.sender].rank == Rank.Pair);
        uint pair = (id+1)/2;
        if(_premeet == false) require(!isVerified(Rank.Pair, pair, _t));
        disputed[_t][pair] = true; 
    }
    function reassign(bool _premeet) external {
        uint _t; if(_premeet == true) _t = t(-1); else _t = t(-2);
        uint id = registry[_t][msg.sender].id;
        require(id != 0);
        uint countPairs = registered[_t][Rank.Pair]/2;
        uint pair;
        if(registry[_t][msg.sender].rank == Rank.Pair) {
            require(registrationPhases[_t][msg.sender] == Registration.Complete);
            pair = (id + 1)/2;
            registry[_t][msg.sender].rank = Rank.Court;
        }
        else pair = 1 + (id - 1)%countPairs;
        require(disputed[_t][pair] == true);
        uint court = 1 + uint(keccak256(abi.encodePacked(msg.sender, pair)))%countPairs;
        uint i = 0;
        while(registryIndex[_t][Rank.Court][court+countPairs*i] != address(0)) i++;
        registry[_t][msg.sender].id = court+countPairs*i;
    }
    function completeVerification() external {
        uint _t = t(-2);
        require(registry[_t][msg.sender].verified == false);
        Rank rank = registry[_t][msg.sender].rank;
        uint id = registry[_t][msg.sender].id;
        uint pair;
        if(rank == Rank.Court) {
            require(isVerified(Rank.Court, id, _t));
            pair = 1 + (id - 1)%(registered[_t][Rank.Pair]/2);
        }
        else pair = (id + 1) /2;
        require(isVerified(Rank.Pair, pair, _t));
        balanceOf[_t+period*2][Token.Personhood][msg.sender]++;
        balanceOf[_t+period*2][Token.Registration][msg.sender]++;
        registry[_t][msg.sender].verified = true;
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
    function verify(address _account) external { _verify(_account, msg.sender, t(-2)); }

    function msgHash(uint _t) internal view returns (bytes32) { return keccak256(abi.encodePacked(msg.sender, _t+period*2)); }

    function uploadSignature(bytes32 r, bytes32 s, uint8 v) external {
        uint _t = t(-2); _verify(msg.sender, ecrecover(msgHash(_t), v, r, s), _t);
    }
    function courtSignature(bytes32[2] calldata r, bytes32[2] calldata s, uint8[2] calldata v) external {
        uint _t = t(-2); bytes32 _msgHash = msgHash(_t);
        _verify(msg.sender, ecrecover(_msgHash, v[0], r[0], s[0]), _t);
        _verify(msg.sender, ecrecover(_msgHash, v[1], r[1], s[1]), _t);
    }
    function claimPersonhood() external {
        uint _t = schedule();
        require(proofOfPersonhood[_t][msg.sender] == 0 && balanceOf[_t][Token.Personhood][msg.sender] >= 1);
        balanceOf[_t][Token.Personhood][msg.sender]--;
        population[_t]++;
        proofOfPersonhood[_t][msg.sender] = population[_t];
        personhoodIndex[_t][population[_t]] = msg.sender;
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
        uint _t = schedule();
        require(allowed[_t][_token][_from][msg.sender] >= _value);
        _transfer(_t, _from, _to, _value, _token);
        allowed[_t][_token][_from][msg.sender] -= _value;
    }
    function vote(uint _id) external {
        uint _t = schedule(); 
        require(inState(rngvote, randomize, _t)); 
        require(_id < registered[_t][Rank.Pair]);

        require(registrationPhases[_t][msg.sender] == Registration.Commit);
        registrationPhases[_t][msg.sender] = Registration.Vote;

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
