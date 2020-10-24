contract Polytopia {

    uint constant public period = 4 weeks;
    uint constant public genesis = 1604127600;

    uint constant public randomize = 2 weeks;
    uint constant public premeet = 3 weeks;

    uint public hour;

    function schedule() public view returns (uint) { return genesis + ((block.timestamp - genesis) / period) * period; }

    uint public entropy;

    enum Rank { Court, Pair }

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
    mapping (uint => mapping (address => bool)) public committed;
    mapping (uint => mapping (Rank => mapping (uint => bool[2]))) public judgement;
    mapping (uint => mapping (uint => bool)) public disputed;

    mapping (uint => uint) public population;
    mapping (uint => mapping (address => uint)) public proofOfPersonhood;
    mapping (uint => mapping (uint => address)) public personhoodIndex;

    mapping (uint => mapping (Token => mapping (address => uint))) public balanceOf;
    mapping (uint => mapping (Token => mapping (address => mapping (address => uint)))) public allowed;

    function inState(uint _prev, uint _next, uint t) internal view returns (bool) {
        if(_prev != 0) return (block.timestamp > t + _prev);
        if(_next != 0) return (block.timestamp < t + _next);
    }

    constructor() public {
        address genesisAccount;
        uint genesisPopulation;
        balanceOf[schedule()][Token.Registration][genesisAccount] = genesisPopulation;
    }

    function _shuffle(uint _t) internal {
        if(shuffled[_t] == 0) {
            entropy = uint(blockhash(block.number-1));
            hour = (entropy%24)*1 hours;
        }
        shuffled[_t]++;
        uint _shuffled = shuffled[_t];
        uint randomNumber = _shuffled + entropy%(registered[_t][Rank.Pair] + 1 - _shuffled);
        entropy = uint(keccak256(abi.encodePacked(entropy, registryIndex[_t][Rank.Pair][randomNumber])));
        (registryIndex[_t][Rank.Pair][_shuffled], registryIndex[_t][Rank.Pair][randomNumber]) = (registryIndex[_t][Rank.Pair][randomNumber], registryIndex[_t][Rank.Pair][_shuffled]); 
        registry[_t][registryIndex[_t][Rank.Pair][_shuffled]].id = _shuffled;
    }
    function shuffle() external {
        uint t = schedule(); 
        require(inState(randomize, premeet, t));
        require(registry[t][msg.sender].rank == Rank.Pair && committed[t][msg.sender] == false);
        committed[t][msg.sender] = true;
        _shuffle(t);
    }
    function lateShuffle(uint _iterations) external { 
        uint t = schedule();
        require(inState(premeet, 0, t));
        for (uint i = 0; i < _iterations; i++) _shuffle(t); 
    }

    function register() external {
        uint t = schedule();
        require(inState(0, randomize, t));
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
        require(inState(0, randomize, t));
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
    
    function isVerified(Rank _rank, uint _unit, uint t) public view returns (bool) {
        return (judgement[t][_rank][_unit][0] == true && judgement[t][_rank][_unit][1] == true);
    }

    function dispute(bool _premeet) external {
        uint t = schedule();
        if(_premeet != true) t -= period;
        uint id = registry[t][msg.sender].id;
        require(registry[t][msg.sender].rank == Rank.Pair && id != 0);
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
    function _verify(address _account, address _signer, uint t) internal {
        require(inState(hour, 0, t));
        require(_account != _signer);
        uint id = registry[t][_account].id;
        require(id != 0);
        uint peer = registry[t][_signer].id;
        require(registry[t][_signer].rank == Rank.Pair && committed[t][_signer] == true && peer != 0);
        Rank rank = registry[t][_account].rank;
        uint unit;
        uint pair;
        if(rank == Rank.Pair) {
            pair = (id + 1)/2;
            unit = pair;
        }
        else {
            unit = id;
            pair = 1 + (unit - 1)%(registered[t][Rank.Pair]/2);
        }
        require(disputed[t][pair] == false);
        require(pair == (peer+1)/2);
        judgement[t][rank][unit][peer%2] = true;
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
    function transfer(uint t, address _from, address to, uint _value, Token _token) internal { 
        require(balanceOf[t][_token][_from] >= _value);
        balanceOf[t][_token][_from] -= _value;
        balanceOf[t][_token][to] += _value;        
    }
    function transfer(address to, uint _value, Token _token) external {
        transfer(schedule(), msg.sender, to, _value, _token);
    }
    function approve(address _spender, uint _value, Token _token) external {
        allowed[schedule()][_token][msg.sender][_spender] = _value;
    }
    function transferFrom(address _from, address to, uint _value, Token _token) external {
        uint t = schedule();
        require(allowed[t][_token][_from][msg.sender] >= _value);
        transfer(t, _from, to, _value, _token);
        allowed[t][_token][_from][msg.sender] -= _value;
    }
}
