// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import "./interfaces/IRouter.sol";
import "./interfaces/IVault.sol";
import "./interfaces/IPositionRouter.sol";
import "./interfaces/IPositionRouterCallbackReceiver.sol";

import "../libraries/utils/Address.sol";
import "../peripherals/interfaces/ITimelock.sol";
import "./BasePositionManager.sol";

contract PositionRouter is BasePositionManager, IPositionRouter {
    using Address for address;

    //开仓请求
    struct IncreasePositionRequest {
        address account;
        address[] path;
        address indexToken;
        uint256 amountIn;
        uint256 minOut;
        uint256 sizeDelta;
        bool isLong;
        uint256 acceptablePrice;
        uint256 executionFee;
        uint256 blockNumber;
        uint256 blockTime;
        bool hasCollateralInETH;
        address callbackTarget;
    }

    //平仓请求
    struct DecreasePositionRequest {
        address account;
        address[] path;
        address indexToken;
        uint256 collateralDelta;
        uint256 sizeDelta;
        bool isLong;
        address receiver;
        uint256 acceptablePrice;
        uint256 minOut;
        uint256 executionFee;
        uint256 blockNumber;
        uint256 blockTime;
        bool withdrawETH;
        address callbackTarget;
    }

    uint256 public minExecutionFee;//最小执行费用

    uint256 public minBlockDelayKeeper;//最小区块延时keeper就能执行,目前是0,相当于超过1个区块就可以开,平仓
    uint256 public minTimeDelayPublic;//最小延时
    uint256 public maxTimeDelay;//最大延时

    bool public isLeverageEnabled = true;//是否启用杠杆

    bytes32[] public increasePositionRequestKeys;//开仓请求key
    bytes32[] public decreasePositionRequestKeys;//平仓请求key

    uint256 public override increasePositionRequestKeysStart;//开仓请求key start
    uint256 public override decreasePositionRequestKeysStart;//平仓请求key start

    uint256 public callbackGasLimit;//回调gas限制

    mapping (address => bool) public isPositionKeeper;//是否是仓位keeper

    mapping (address => uint256) public increasePositionsIndex;//开仓下标
    mapping (bytes32 => IncreasePositionRequest) public increasePositionRequests;//开仓请求

    mapping (address => uint256) public decreasePositionsIndex;//平仓下标
    mapping (bytes32 => DecreasePositionRequest) public decreasePositionRequests;//平仓请求

    event CreateIncreasePosition(
        address indexed account,
        address[] path,
        address indexToken,
        uint256 amountIn,
        uint256 minOut,
        uint256 sizeDelta,
        bool isLong,
        uint256 acceptablePrice,
        uint256 executionFee,
        uint256 index,
        uint256 queueIndex,
        uint256 blockNumber,
        uint256 blockTime,
        uint256 gasPrice
    );

    event ExecuteIncreasePosition(
        address indexed account,
        address[] path,
        address indexToken,
        uint256 amountIn,
        uint256 minOut,
        uint256 sizeDelta,
        bool isLong,
        uint256 acceptablePrice,
        uint256 executionFee,
        uint256 blockGap,
        uint256 timeGap
    );

    event CancelIncreasePosition(
        address indexed account,
        address[] path,
        address indexToken,
        uint256 amountIn,
        uint256 minOut,
        uint256 sizeDelta,
        bool isLong,
        uint256 acceptablePrice,
        uint256 executionFee,
        uint256 blockGap,
        uint256 timeGap
    );

    event CreateDecreasePosition(
        address indexed account,
        address[] path,
        address indexToken,
        uint256 collateralDelta,
        uint256 sizeDelta,
        bool isLong,
        address receiver,
        uint256 acceptablePrice,
        uint256 minOut,
        uint256 executionFee,
        uint256 index,
        uint256 queueIndex,
        uint256 blockNumber,
        uint256 blockTime
    );

    event ExecuteDecreasePosition(
        address indexed account,
        address[] path,
        address indexToken,
        uint256 collateralDelta,
        uint256 sizeDelta,
        bool isLong,
        address receiver,
        uint256 acceptablePrice,
        uint256 minOut,
        uint256 executionFee,
        uint256 blockGap,
        uint256 timeGap
    );

    event CancelDecreasePosition(
        address indexed account,
        address[] path,
        address indexToken,
        uint256 collateralDelta,
        uint256 sizeDelta,
        bool isLong,
        address receiver,
        uint256 acceptablePrice,
        uint256 minOut,
        uint256 executionFee,
        uint256 blockGap,
        uint256 timeGap
    );

    event SetPositionKeeper(address indexed account, bool isActive);
    event SetMinExecutionFee(uint256 minExecutionFee);
    event SetIsLeverageEnabled(bool isLeverageEnabled);
    event SetDelayValues(uint256 minBlockDelayKeeper, uint256 minTimeDelayPublic, uint256 maxTimeDelay);
    event SetRequestKeysStartValues(uint256 increasePositionRequestKeysStart, uint256 decreasePositionRequestKeysStart);
    event SetCallbackGasLimit(uint256 callbackGasLimit);
    event Callback(address callbackTarget, bool success);

    modifier onlyPositionKeeper() {
        require(isPositionKeeper[msg.sender], "403");
        _;
    }

    constructor(
        address _vault,
        address _router,
        address _weth,
        address _shortsTracker,
        uint256 _depositFee,
        uint256 _minExecutionFee
    ) public BasePositionManager(_vault, _router, _shortsTracker, _weth, _depositFee) {
        minExecutionFee = _minExecutionFee;
    }

    //admin设置keeper
    function setPositionKeeper(address _account, bool _isActive) external onlyAdmin {
        isPositionKeeper[_account] = _isActive;
        emit SetPositionKeeper(_account, _isActive);
    }

    //设置gasLimit
    function setCallbackGasLimit(uint256 _callbackGasLimit) external onlyAdmin {
        callbackGasLimit = _callbackGasLimit;
        emit SetCallbackGasLimit(_callbackGasLimit);
    }

    //设置最小执行费用
    function setMinExecutionFee(uint256 _minExecutionFee) external onlyAdmin {
        minExecutionFee = _minExecutionFee;
        emit SetMinExecutionFee(_minExecutionFee);
    }

    //设置杠杆是否启用
    function setIsLeverageEnabled(bool _isLeverageEnabled) external onlyAdmin {
        isLeverageEnabled = _isLeverageEnabled;
        emit SetIsLeverageEnabled(_isLeverageEnabled);
    }

    //设置延迟
    function setDelayValues(uint256 _minBlockDelayKeeper, uint256 _minTimeDelayPublic, uint256 _maxTimeDelay) external onlyAdmin {
        minBlockDelayKeeper = _minBlockDelayKeeper;
        minTimeDelayPublic = _minTimeDelayPublic;
        maxTimeDelay = _maxTimeDelay;
        emit SetDelayValues(_minBlockDelayKeeper, _minTimeDelayPublic, _maxTimeDelay);
    }

    //设置开平仓keys开始值
    function setRequestKeysStartValues(uint256 _increasePositionRequestKeysStart, uint256 _decreasePositionRequestKeysStart) external onlyAdmin {
        increasePositionRequestKeysStart = _increasePositionRequestKeysStart;
        decreasePositionRequestKeysStart = _decreasePositionRequestKeysStart;

        emit SetRequestKeysStartValues(_increasePositionRequestKeysStart, _decreasePositionRequestKeysStart);
    }

   //keeper批量执行开仓单
    function executeIncreasePositions(uint256 _endIndex, address payable _executionFeeReceiver) external override onlyPositionKeeper {
        uint256 index = increasePositionRequestKeysStart;
        uint256 length = increasePositionRequestKeys.length;

        if (index >= length) { return; }

        if (_endIndex > length) {
            _endIndex = length;
        }

        //从合约start下标开始执行合约到传入的endIndex
        while (index < _endIndex) {
            bytes32 key = increasePositionRequestKeys[index];

            // if the request was executed then delete the key from the array
            // if the request was not executed then break from the loop, this can happen if the
            // minimum number of blocks has not yet passed
            // an error could be thrown if the request is too old or if the slippage is
            // higher than what the user specified, or if there is insufficient liquidity for the position
            // in case an error was thrown, cancel the request
            //如果请求已执行，则从数组中删除密钥如果请求未执行，则从循环中断，如果
            //尚未通过最小块数如果请求太旧或延迟太长，则可能引发错误
            //高于用户指定的金额，或头寸流动性不足如果抛出错误，请取消请求
            try this.executeIncreasePosition(key, _executionFeeReceiver) returns (bool _wasExecuted) {
                if (!_wasExecuted) { break; }
            } catch {
                // wrap this call in a try catch to prevent invalid cancels from blocking the loop
                try this.cancelIncreasePosition(key, _executionFeeReceiver) returns (bool _wasCancelled) {
                    if (!_wasCancelled) { break; }
                } catch {}
            }

            delete increasePositionRequestKeys[index];
            index++;
        }

        //更新下标
        increasePositionRequestKeysStart = index;
    }

    //keeper批量执行平仓单
    function executeDecreasePositions(uint256 _endIndex, address payable _executionFeeReceiver) external override onlyPositionKeeper {
        uint256 index = decreasePositionRequestKeysStart;
        uint256 length = decreasePositionRequestKeys.length;

        if (index >= length) { return; }

        if (_endIndex > length) {
            _endIndex = length;
        }

        //从index开始平仓
        while (index < _endIndex) {
            bytes32 key = decreasePositionRequestKeys[index];

            // if the request was executed then delete the key from the array
            // if the request was not executed then break from the loop, this can happen if the
            // minimum number of blocks has not yet passed
            // an error could be thrown if the request is too old
            // in case an error was thrown, cancel the request
            //如果请求已执行，则从数组中删除密钥,如果请求未执行，则从循环中断，如果尚未通过
            //最小块数,如果请求太旧，则可能引发错误,如果抛出错误，请取消请求
            try this.executeDecreasePosition(key, _executionFeeReceiver) returns (bool _wasExecuted) {
                if (!_wasExecuted) { break; }
            } catch {
                // wrap this call in a try catch to prevent invalid cancels from blocking the loop
                try this.cancelDecreasePosition(key, _executionFeeReceiver) returns (bool _wasCancelled) {
                    if (!_wasCancelled) { break; }
                } catch {}
            }

            delete decreasePositionRequestKeys[index];
            index++;
        }

        //更新下标
        decreasePositionRequestKeysStart = index;
    }

    //创建开仓
    function createIncreasePosition(
        address[] memory _path,
        address _indexToken,
        uint256 _amountIn,
        uint256 _minOut,
        uint256 _sizeDelta,
        bool _isLong,
        uint256 _acceptablePrice,
        uint256 _executionFee,
        bytes32 _referralCode,
        address _callbackTarget
    ) external payable nonReentrant returns (bytes32) {
        // 需要提供的_executionFee大于等于minExecutionFee
        require(_executionFee >= minExecutionFee, "fee");
        // _executionFee需要提前转过来
        require(msg.value == _executionFee, "val");
        // path的长度1,2
        require(_path.length == 1 || _path.length == 2, "len");

        //将转入的eth转成weth
        _transferInETH();

        //referralCode不为空,则设置交易员注册码
        _setTraderReferralCode(_referralCode);

        //_amountIn大于0
        if (_amountIn > 0) {
            //验证sender是否是插件,将sender的钱转到当前合约地址
            IRouter(router).pluginTransfer(_path[0], msg.sender, address(this), _amountIn);
        }

        //创建开仓,存储request
        return _createIncreasePosition(
            msg.sender,
            _path,
            _indexToken,
            _amountIn,
            _minOut,
            _sizeDelta,
            _isLong,
            _acceptablePrice,
            _executionFee,
            false,
            _callbackTarget
        );
    }

    //创建eth开仓
    function createIncreasePositionETH(
        address[] memory _path,
        address _indexToken,
        uint256 _minOut,
        uint256 _sizeDelta,
        bool _isLong,
        uint256 _acceptablePrice,
        uint256 _executionFee,
        bytes32 _referralCode,
        address _callbackTarget
    ) external payable nonReentrant returns (bytes32) {
        // 需要提供的_executionFee大于等于minExecutionFee
        require(_executionFee >= minExecutionFee, "fee");
        // _executionFee需要提前转过来
        require(msg.value >= _executionFee, "val");
        // path的长度1,2
        require(_path.length == 1 || _path.length == 2, "len");
        // 并且第1个token必须是weth
        require(_path[0] == weth, "path");
        // 转入eth
        _transferInETH();
        
        // 设置注册码
        _setTraderReferralCode(_referralCode);

        //计算真实amountIn
        uint256 amountIn = msg.value.sub(_executionFee);

        return _createIncreasePosition(
            msg.sender,
            _path,
            _indexToken,
            amountIn,
            _minOut,
            _sizeDelta,
            _isLong,
            _acceptablePrice,
            _executionFee,
            true,
            _callbackTarget
        );
    }

    //创建平仓单
    function createDecreasePosition(
        address[] memory _path,
        address _indexToken,
        uint256 _collateralDelta,
        uint256 _sizeDelta,
        bool _isLong,
        address _receiver,
        uint256 _acceptablePrice,
        uint256 _minOut,
        uint256 _executionFee,
        bool _withdrawETH,
        address _callbackTarget
    ) external payable nonReentrant returns (bytes32) {
        // 需要提供的_executionFee大于等于minExecutionFee
        require(_executionFee >= minExecutionFee, "fee");
        // _executionFee需要提前转过来
        require(msg.value == _executionFee, "val");
        // path的长度1,2
        require(_path.length == 1 || _path.length == 2, "len");

        // 如果需要提eth,path最后得是eth
        if (_withdrawETH) {
            require(_path[_path.length - 1] == weth, "path");
        }

        // 先把eth转进来
        _transferInETH();

        return _createDecreasePosition(
            msg.sender,
            _path,
            _indexToken,
            _collateralDelta,
            _sizeDelta,
            _isLong,
            _receiver,
            _acceptablePrice,
            _minOut,
            _executionFee,
            _withdrawETH,
            _callbackTarget
        );
    }

    //获取请求队列长度
    function getRequestQueueLengths() external view returns (uint256, uint256, uint256, uint256) {
        return (
            increasePositionRequestKeysStart,
            increasePositionRequestKeys.length,
            decreasePositionRequestKeysStart,
            decreasePositionRequestKeys.length
        );
    }

    //执行开仓请求
    function executeIncreasePosition(bytes32 _key, address payable _executionFeeReceiver) public nonReentrant returns (bool) {
        //先获取开仓单
        IncreasePositionRequest memory request = increasePositionRequests[_key];
        // if the request was already executed or cancelled, return true so that the executeIncreasePositions loop will continue executing the next request
        //如果请求已被执行或取消，则返回true，以便executeIncreasePositions循环将继续执行下一个请求
        if (request.account == address(0)) { return true; }

        //校验区块时间是否能被执行,keeper无限制,用户自己则需要等180个块,3秒一个块的话,相当于要等9分钟才能开下一单
        bool shouldExecute = _validateExecution(request.blockNumber, request.blockTime, request.account);
        if (!shouldExecute) { return false; }

        delete increasePositionRequests[_key];

        //如果传入大于0
        if (request.amountIn > 0) {
            uint256 amountIn = request.amountIn;

            //path有3种以上代币,则先转换出最终的的amountIn
            if (request.path.length > 1) {
                IERC20(request.path[0]).safeTransfer(vault, request.amountIn);
                amountIn = _swap(request.path, request.minOut, address(this));
            }

            //gmx_update
            //获取开仓单,这里传入的是msg.sender,如果是keeper调用,有可能获取不到用户的单,所以应该使用最新的代码,传入account
            //计算去除手续费的费用,并转入vault
            uint256 afterFeeAmount = _collectFees(msg.sender, request.path, amountIn, request.indexToken, request.isLong, request.sizeDelta);
            IERC20(request.path[request.path.length - 1]).safeTransfer(vault, afterFeeAmount);
        }

        //验证头寸,使用router开仓,并更新空头头寸
        _increasePosition(request.account, request.path[request.path.length - 1], request.indexToken, request.sizeDelta, request.isLong, request.acceptablePrice);

        //将手续费从当前合约转到receiver账号,_executionFeeReceiver就是keeper
        _transferOutETHWithGasLimitIgnoreFail(request.executionFee, _executionFeeReceiver);

        emit ExecuteIncreasePosition(
            request.account,
            request.path,
            request.indexToken,
            request.amountIn,
            request.minOut,
            request.sizeDelta,
            request.isLong,
            request.acceptablePrice,
            request.executionFee,
            block.number.sub(request.blockNumber),
            block.timestamp.sub(request.blockTime)
        );

        //设置了回调,则callback
        _callRequestCallback(request.callbackTarget, _key, true, true);

        return true;
    }

    //取消开仓 
    function cancelIncreasePosition(bytes32 _key, address payable _executionFeeReceiver) public nonReentrant returns (bool) {
        IncreasePositionRequest memory request = increasePositionRequests[_key];
        // if the request was already executed or cancelled, return true so that the executeIncreasePositions loop will continue executing the next request
        // 如果请求已被执行或取消，则返回true，以便executeIncreasePositions循环将继续执行下一个请求
        if (request.account == address(0)) { return true; }

        //是否应该验证取消
        bool shouldCancel = _validateCancellation(request.blockNumber, request.blockTime, request.account);
        if (!shouldCancel) { return false; }

        //如果可取消,则删除key
        delete increasePositionRequests[_key];

        //如果质押了eth
        if (request.hasCollateralInETH) {
            //则将amountIn转给请求中设置的账户
            _transferOutETHWithGasLimitIgnoreFail(request.amountIn, payable(request.account));
        } else {
            //否则将path[0]代币转给设置的账户
            IERC20(request.path[0]).safeTransfer(request.account, request.amountIn);
        }

        //将手续费转给account或者keeper
       _transferOutETHWithGasLimitIgnoreFail(request.executionFee, _executionFeeReceiver);

        emit CancelIncreasePosition(
            request.account,
            request.path,
            request.indexToken,
            request.amountIn,
            request.minOut,
            request.sizeDelta,
            request.isLong,
            request.acceptablePrice,
            request.executionFee,
            block.number.sub(request.blockNumber),
            block.timestamp.sub(request.blockTime)
        );

        //回调
        _callRequestCallback(request.callbackTarget, _key, false, true);

        return true;
    }

    function executeDecreasePosition(bytes32 _key, address payable _executionFeeReceiver) public nonReentrant returns (bool) {
        DecreasePositionRequest memory request = decreasePositionRequests[_key];
        // if the request was already executed or cancelled, return true so that the executeDecreasePositions loop will continue executing the next request
        if (request.account == address(0)) { return true; }

        bool shouldExecute = _validateExecution(request.blockNumber, request.blockTime, request.account);
        if (!shouldExecute) { return false; }

        delete decreasePositionRequests[_key];

        uint256 amountOut = _decreasePosition(request.account, request.path[0], request.indexToken, request.collateralDelta, request.sizeDelta, request.isLong, address(this), request.acceptablePrice);

        if (amountOut > 0) {
            if (request.path.length > 1) {
                IERC20(request.path[0]).safeTransfer(vault, amountOut);
                amountOut = _swap(request.path, request.minOut, address(this));
            }

            if (request.withdrawETH) {
               _transferOutETHWithGasLimitIgnoreFail(amountOut, payable(request.receiver));
            } else {
               IERC20(request.path[request.path.length - 1]).safeTransfer(request.receiver, amountOut);
            }
        }

       _transferOutETHWithGasLimitIgnoreFail(request.executionFee, _executionFeeReceiver);

        emit ExecuteDecreasePosition(
            request.account,
            request.path,
            request.indexToken,
            request.collateralDelta,
            request.sizeDelta,
            request.isLong,
            request.receiver,
            request.acceptablePrice,
            request.minOut,
            request.executionFee,
            block.number.sub(request.blockNumber),
            block.timestamp.sub(request.blockTime)
        );

        _callRequestCallback(request.callbackTarget, _key, true, false);

        return true;
    }

    function cancelDecreasePosition(bytes32 _key, address payable _executionFeeReceiver) public nonReentrant returns (bool) {
        DecreasePositionRequest memory request = decreasePositionRequests[_key];
        // if the request was already executed or cancelled, return true so that the executeDecreasePositions loop will continue executing the next request
        if (request.account == address(0)) { return true; }

        bool shouldCancel = _validateCancellation(request.blockNumber, request.blockTime, request.account);
        if (!shouldCancel) { return false; }

        delete decreasePositionRequests[_key];

       _transferOutETHWithGasLimitIgnoreFail(request.executionFee, _executionFeeReceiver);

        emit CancelDecreasePosition(
            request.account,
            request.path,
            request.indexToken,
            request.collateralDelta,
            request.sizeDelta,
            request.isLong,
            request.receiver,
            request.acceptablePrice,
            request.minOut,
            request.executionFee,
            block.number.sub(request.blockNumber),
            block.timestamp.sub(request.blockTime)
        );

        _callRequestCallback(request.callbackTarget, _key, false, false);

        return true;
    }

    //hash(account+index)
    function getRequestKey(address _account, uint256 _index) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(_account, _index));
    }

    function getIncreasePositionRequestPath(bytes32 _key) public view returns (address[] memory) {
        IncreasePositionRequest memory request = increasePositionRequests[_key];
        return request.path;
    }

    function getDecreasePositionRequestPath(bytes32 _key) public view returns (address[] memory) {
        DecreasePositionRequest memory request = decreasePositionRequests[_key];
        return request.path;
    }

    // referralCode不为空,则设置交易员注册码
    function _setTraderReferralCode(bytes32 _referralCode) internal {
        if (_referralCode != bytes32(0) && referralStorage != address(0)) {
            IReferralStorage(referralStorage).setTraderReferralCode(msg.sender, _referralCode);
        }
    }

    //验证账户的单是否可执行
    function _validateExecution(uint256 _positionBlockNumber, uint256 _positionBlockTime, address _account) internal view returns (bool) {
        //超过30分钟就不能执行了
        if (_positionBlockTime.add(maxTimeDelay) <= block.timestamp) {
            revert("expired");
        }

        //需要调用者是keeper
        bool isKeeperCall = msg.sender == address(this) || isPositionKeeper[msg.sender];

        //如果不是keeper并且也没开杠杆则报错,相当于是keeper+开启杠杆,或者非keeper+不开启杠杆都可以执行
        if (!isLeverageEnabled && !isKeeperCall) {
            revert("403");
        }

        //是keeper则返回:交易的创建区块+最小延迟<=当前区块,由于最小延迟目前是0,所以除了一个区块内不能执行,其它情况都能执行
        if (isKeeperCall) {
            return _positionBlockNumber.add(minBlockDelayKeeper) <= block.number;
        }

        require(msg.sender == _account, "403");

        //如果是用户自己,则需要等一定时间(当前链上180个块)才能执行
        require(_positionBlockTime.add(minTimeDelayPublic) <= block.timestamp, "delay");

        return true;
    }

    //验证取消
    function _validateCancellation(uint256 _positionBlockNumber, uint256 _positionBlockTime, address _account) internal view returns (bool) {
        // 是否是keeper调用,或者交易的发送者是当前合约
        bool isKeeperCall = msg.sender == address(this) || isPositionKeeper[msg.sender];

        // keeper且开启杠杆,或者非keeper且不开启杠杆才可以执行
        if (!isLeverageEnabled && !isKeeperCall) {
            revert("403");
        }

        //是keeper则返回:交易的创建区块+最小延迟<=当前区块,由于最小延迟目前是0,所以除了一个区块内不能执行,其它情况都能执行
        if (isKeeperCall) {
            return _positionBlockNumber.add(minBlockDelayKeeper) <= block.number;
        }

        require(msg.sender == _account, "403");

        //如果是用户自己,则需要等一定时间(当前链上180个块)才能执行
        require(_positionBlockTime.add(minTimeDelayPublic) <= block.timestamp, "delay");

        return true;
    }

    //创建开仓,存储request
    function _createIncreasePosition(
        address _account,
        address[] memory _path,
        address _indexToken,
        uint256 _amountIn,
        uint256 _minOut,
        uint256 _sizeDelta,
        bool _isLong,
        uint256 _acceptablePrice,
        uint256 _executionFee,
        bool _hasCollateralInETH,
        address _callbackTarget
    ) internal returns (bytes32) {
        //构造开仓请求
        IncreasePositionRequest memory request = IncreasePositionRequest(
            _account,
            _path,
            _indexToken,
            _amountIn,
            _minOut,
            _sizeDelta,
            _isLong,
            _acceptablePrice,
            _executionFee,
            block.number,
            block.timestamp,
            _hasCollateralInETH,
            _callbackTarget
        );

        //存储开仓请求
        (uint256 index, bytes32 requestKey) = _storeIncreasePositionRequest(request);
        //发送事件
        emit CreateIncreasePosition(
            _account,
            _path,
            _indexToken,
            _amountIn,
            _minOut,
            _sizeDelta,
            _isLong,
            _acceptablePrice,
            _executionFee,
            index,
            increasePositionRequestKeys.length - 1,
            block.number,
            block.timestamp,
            tx.gasprice
        );

        //返回key
        return requestKey;
    }

    //存储开仓请求
    function _storeIncreasePositionRequest(IncreasePositionRequest memory _request) internal returns (uint256, bytes32) {
        address account = _request.account;
        //用户开仓单数
        uint256 index = increasePositionsIndex[account].add(1);
        increasePositionsIndex[account] = index;
        //计算hash(account,index)
        bytes32 key = getRequestKey(account, index);

        //保存request
        increasePositionRequests[key] = _request;
        increasePositionRequestKeys.push(key);

        return (index, key);
    }

    //存储平仓请求
    function _storeDecreasePositionRequest(DecreasePositionRequest memory _request) internal returns (uint256, bytes32) {
        address account = _request.account;
        uint256 index = decreasePositionsIndex[account].add(1);
        decreasePositionsIndex[account] = index;
        bytes32 key = getRequestKey(account, index);

        decreasePositionRequests[key] = _request;
        decreasePositionRequestKeys.push(key);

        return (index, key);
    }

    //创建平仓
    function _createDecreasePosition(
        address _account,
        address[] memory _path,
        address _indexToken,
        uint256 _collateralDelta,
        uint256 _sizeDelta,
        bool _isLong,
        address _receiver,
        uint256 _acceptablePrice,
        uint256 _minOut,
        uint256 _executionFee,
        bool _withdrawETH,
        address _callbackTarget
    ) internal returns (bytes32) {
        //构建平仓请求
        DecreasePositionRequest memory request = DecreasePositionRequest(
            _account,
            _path,
            _indexToken,
            _collateralDelta,
            _sizeDelta,
            _isLong,
            _receiver,
            _acceptablePrice,
            _minOut,
            _executionFee,
            block.number,
            block.timestamp,
            _withdrawETH,
            _callbackTarget
        );

        //存储平仓请求
        (uint256 index, bytes32 requestKey) = _storeDecreasePositionRequest(request);
        emit CreateDecreasePosition(
            request.account,
            request.path,
            request.indexToken,
            request.collateralDelta,
            request.sizeDelta,
            request.isLong,
            request.receiver,
            request.acceptablePrice,
            request.minOut,
            request.executionFee,
            index,
            decreasePositionRequestKeys.length - 1,
            block.number,
            block.timestamp
        );
        return requestKey;
    }

    //合约调用回调
    function _callRequestCallback(
        address _callbackTarget,
        bytes32 _key,
        bool _wasExecuted,
        bool _isIncrease
    ) internal {
        //没有设置回调则直接返回
        if (_callbackTarget == address(0)) {
            return;
        }

        //非合约地址也直接返回  
        if (!_callbackTarget.isContract()) {
            return;
        }

        //如果没设置gas也直接返回
        uint256 _gasLimit = callbackGasLimit;
        if (_gasLimit == 0) {
            return;
        }

        //使用回调地址调用gmxPositionCallback,将_key,_wasExecuted,_isIncrease返回
        bool success;
        try IPositionRouterCallbackReceiver(_callbackTarget).gmxPositionCallback{ gas: _gasLimit }(_key, _wasExecuted, _isIncrease) {
            success = true;
        } catch {}

        emit Callback(_callbackTarget, success);
    }
}