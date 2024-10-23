// SPDX-License-Identifier: MIT
pragma solidity ^0.8.1;

contract MultiSigWallet {
    address[] private owners;
    mapping(address => bool) private isOwner;
    uint private requiredConfirmations;

    struct Transaction {
        address payable recipient;
        uint amount;
        uint confirmations;
        bool executed;
        uint timelockEnd;
    }

    struct RecurringPayment {
        address payable recipient;
        uint amount;
        uint interval; // Dalam detik
        uint nextPayment; // Timestamp kapan pembayaran berikutnya bisa dilakukan
    }

    Transaction[] public transactions;
    RecurringPayment[] public recurringPayments;
    uint constant TIMEDURATION = 1 days; // Durasi timelock
    uint public feePercentage = 70; // 0.7% fee
    bool public paused;

    event LogDeposit(uint amount, address indexed sender);
    event LogWithdrawal(uint amount, address indexed recipient, uint transactionId);
    event TransactionConfirmed(uint transactionId, address indexed owner);
    event TransactionExecuted(uint transactionId, address indexed owner);
    
    modifier onlyOwners() {
        require(isOwner[msg.sender], "Hanya pemilik yang bisa melakukan ini.");
        _;
    }

    modifier transactionExists(uint _txId) {
        require(_txId < transactions.length, "Transaksi tidak ada.");
        _;
    }

    modifier notExecuted(uint _txId) {
        require(!transactions[_txId].executed, "Transaksi sudah dieksekusi.");
        _;
    }

    modifier notConfirmed(uint _txId) {
        require(transactions[_txId].confirmations < requiredConfirmations, "Transaksi sudah dikonfirmasi.");
        _;
    }

    modifier whenNotPaused() {
        require(!paused, "Kontrak sedang dihentikan sementara.");
        _;
    }

    constructor(address[] memory _owners, uint _confirmations) {
        require(_owners.length > 0, "Minimal harus ada satu pemilik.");
        require(_confirmations > 0 && _confirmations <= _owners.length, "Jumlah konfirmasi tidak valid.");

        for (uint i = 0; i < _owners.length; i++) {
            address owner = _owners[i];
            require(owner != address(0), "Pemilik tidak valid.");
            isOwner[owner] = true;
            owners.push(owner);
        }

        requiredConfirmations = _confirmations;
    }

    // Deposit ETH ke dompet
    function deposit() public payable {
        require(msg.value > 0, "Harus mengirim ETH.");
        emit LogDeposit(msg.value, msg.sender);
    }

    // Ajukan penarikan ETH dengan timelock
    function submitWithdrawal(uint amount, address payable recipient) public onlyOwners whenNotPaused {
        require(amount <= address(this).balance, "Dana tidak cukup.");

        transactions.push(Transaction({
            recipient: recipient,
            amount: amount,
            confirmations: 0,
            executed: false,
            timelockEnd: block.timestamp + TIMEDURATION
        }));
    }

    // Konfirmasi penarikan
    function confirmTransaction(uint _txId) public onlyOwners transactionExists(_txId) notExecuted(_txId) notConfirmed(_txId) {
        Transaction storage transaction = transactions[_txId];
        transaction.confirmations += 1;

        emit TransactionConfirmed(_txId, msg.sender);

        // Jika cukup konfirmasi, lakukan penarikan setelah timelock selesai
        if (transaction.confirmations >= requiredConfirmations && block.timestamp >= transaction.timelockEnd) {
            executeTransaction(_txId);
        }
    }

    // Eksekusi penarikan dengan biaya
    function executeTransaction(uint _txId) public onlyOwners transactionExists(_txId) notExecuted(_txId) {
        Transaction storage transaction = transactions[_txId];
        require(transaction.confirmations >= requiredConfirmations, "Konfirmasi belum cukup.");
        require(block.timestamp >= transaction.timelockEnd, "Timelock belum selesai.");

        transaction.executed = true;

        // Hitung dan transfer biaya
        uint fee = calculateFee(transaction.amount);
        uint amountAfterFee = transaction.amount - fee;

        transaction.recipient.transfer(amountAfterFee);
        payable(owners[0]).transfer(fee); // Kirim fee ke pemilik pertama sebagai contoh

        emit LogWithdrawal(amountAfterFee, transaction.recipient, _txId);
        emit TransactionExecuted(_txId, msg.sender);
    }

    // Hitung biaya
    function calculateFee(uint amount) internal view returns (uint) {
        return (amount * feePercentage) / 10000; // Menggunakan 10000 untuk menghitung 0.7%
    }

    // Tambahkan pembayaran berulang
    function addRecurringPayment(address payable recipient, uint amount, uint interval) public onlyOwners {
        recurringPayments.push(RecurringPayment({
            recipient: recipient,
            amount: amount,
            interval: interval,
            nextPayment: block.timestamp + interval
        }));
    }

    // Eksekusi pembayaran berulang
    function executeRecurringPayment(uint paymentId) public onlyOwners {
        RecurringPayment storage payment = recurringPayments[paymentId];
        require(block.timestamp >= payment.nextPayment, "Belum waktunya pembayaran.");
        require(address(this).balance >= payment.amount, "Dana tidak cukup.");

        payment.nextPayment = block.timestamp + payment.interval;
        payment.recipient.transfer(payment.amount);
    }

    // Penarikan darurat
    function emergencyWithdraw() public onlyOwners whenPaused {
        for (uint i = 0; i < owners.length; i++) {
            address payable ownerAddress = payable(owners[i]);
            ownerAddress.transfer(address(this).balance / owners.length);
        }
    }

    // Fungsi untuk menghentikan sementara penarikan
    function pause() public onlyOwners {
        paused = true;
    }

    // Fungsi untuk melanjutkan penarikan
    function unpause() public onlyOwners {
        paused = false;
    }
}
