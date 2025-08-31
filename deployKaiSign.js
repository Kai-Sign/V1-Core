const { ethers } = require('ethers');
const fs = require('fs');
const path = require('path');

async function deployKaiSign() {
    // Configuration
    const RPC_URL = 'https://eth-sepolia.g.alchemy.com/v2/1EFr4OH_BpQp-qxV_7Vv5';
    const provider = new ethers.JsonRpcProvider(RPC_URL);
    
    // Get private key from environment
    const privateKey = process.env.PRIVATE_KEY;
    if (!privateKey) {
        console.error('Please set PRIVATE_KEY environment variable');
        process.exit(1);
    }
    
    const wallet = new ethers.Wallet(privateKey, provider);
    console.log('Deploying from:', wallet.address);
    
    // Read compiled contract
    const contractPath = path.join(__dirname, 'out/KaiSign.sol/KaiSign.json');
    const contractJson = JSON.parse(fs.readFileSync(contractPath, 'utf8'));
    
    // Constructor parameters
    const realityETH = '0xaf33DcB6E8c5c4D9dDF579f53031b514d19449CA'; // Reality.eth on Sepolia
    const arbitrator = '0x05B942fAEcfB3924970E3A28e0F230910CEDFF45'; // Arbitrator address
    const treasury = '0x7D8730aD11f0D421bd41c6E5584F20c744CBAf29'; // Treasury address
    const minBond = ethers.parseEther('0.01'); // 0.01 ETH
    const initialAdmins = [wallet.address];
    
    // Deploy with CREATE2 for deterministic address
    const salt = '0x319d4829c8512c09bedf1688c873a330c0c0888875b02da9f06256b59c99ee36';
    
    console.log('\n=== DEPLOYING KAISIGN CONTRACT ===');
    console.log('Reality.eth:', realityETH);
    console.log('Arbitrator:', arbitrator);
    console.log('Treasury:', treasury);
    console.log('Min Bond:', ethers.formatEther(minBond), 'ETH');
    console.log('Initial Admin:', wallet.address);
    console.log('Salt:', salt);
    
    // Create contract factory
    const factory = new ethers.ContractFactory(
        contractJson.abi,
        contractJson.bytecode.object,
        wallet
    );
    
    // Calculate CREATE2 address
    const deployTransaction = await factory.getDeployTransaction(
        realityETH,
        arbitrator,
        treasury,
        minBond,
        initialAdmins
    );
    
    const initCodeHash = ethers.keccak256(deployTransaction.data);
    
    // For CREATE2, we need to use a factory contract
    // Since we don't have one deployed, we'll use regular deployment
    console.log('\nDeploying contract...');
    
    const contract = await factory.deploy(
        realityETH,
        arbitrator,
        treasury,
        minBond,
        initialAdmins
    );
    
    console.log('Transaction hash:', contract.deploymentTransaction().hash);
    console.log('Waiting for confirmation...');
    
    await contract.waitForDeployment();
    const address = await contract.getAddress();
    
    console.log('\n=== DEPLOYMENT SUCCESSFUL ===');
    console.log('KaiSign deployed to:', address);
    console.log('Transaction:', contract.deploymentTransaction().hash);
    
    // Verify deployment
    const code = await provider.getCode(address);
    if (code === '0x') {
        console.error('ERROR: No code at deployed address!');
        process.exit(1);
    }
    
    console.log('\n=== NEXT STEPS ===');
    console.log('1. Update KAISIGN_ADDRESS in script/InteractWithBlob.s.sol to:', address);
    console.log('2. Run ./run_commit.sh to commit your blob hash');
    console.log('3. Wait 5 minutes');
    console.log('4. Run ./run_reveal.sh <commitment_id> to reveal and bond');
    
    // Save deployment info
    const deploymentInfo = {
        address: address,
        transactionHash: contract.deploymentTransaction().hash,
        blockNumber: contract.deploymentTransaction().blockNumber,
        deployer: wallet.address,
        timestamp: new Date().toISOString(),
        network: 'sepolia',
        constructorArgs: {
            realityETH,
            arbitrator,
            treasury,
            minBond: ethers.formatEther(minBond),
            initialAdmins
        }
    };
    
    fs.writeFileSync(
        'kaisign-deployment.json',
        JSON.stringify(deploymentInfo, null, 2)
    );
    console.log('\nDeployment info saved to kaisign-deployment.json');
}

// Run deployment
deployKaiSign().catch(console.error);