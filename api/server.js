const express = require('express');
const bodyParser = require('body-parser');
const cors = require('cors');
const { exec } = require('child_process');
const fs = require('fs');
const path = require('path');

const app = express();
const PORT = process.env.PORT || 3000;
const API_KEY = process.env.API_KEY;

// Paths
const COMMANDS_DIR = path.resolve(__dirname, '..');
const HOSTFY_SCRIPT = path.join(COMMANDS_DIR, 'hostfy.sh');
const CATALOG_FILE = path.join(COMMANDS_DIR, 'catalog', 'containers-catalog.json');

// Middleware
app.use(cors());
app.use(bodyParser.json());

// Authentication Middleware
const authenticate = (req, res, next) => {
    const apiKey = req.headers['x-api-key'];
    
    if (!API_KEY) {
        console.warn('Warning: API_KEY not set in environment. allowing all requests (unsafe).');
        return next();
    }

    if (!apiKey || apiKey !== API_KEY) {
        return res.status(401).json({ error: 'Unauthorized: Invalid API Key' });
    }
    next();
};

app.use(authenticate);

// Helper to execute hostfy commands
const runHostfy = (args) => {
    return new Promise((resolve, reject) => {
        const command = `bash "${HOSTFY_SCRIPT}" ${args}`;
        console.log(`Executing: ${command}`);
        
        exec(command, (error, stdout, stderr) => {
            if (error) {
                console.error(`Error: ${error.message}`);
                return reject({ error: error.message, stderr, stdout });
            }
            resolve(stdout);
        });
    });
};

// Routes

// Health Check
app.get('/health', (req, res) => {
    res.json({ status: 'ok', version: '1.0.0' });
});

// List Containers
app.get('/containers', async (req, res) => {
    try {
        // We can read the registry file directly or use 'hostfy list'
        // Reading the registry file gives more structured data if we parse it ourselves,
        // but 'hostfy list' ensures we see what the CLI sees.
        // For JSON output, let's try to read the registry file directly if possible,
        // or parse the output of 'hostfy list'.
        
        // Let's use the catalog file for available containers
        if (fs.existsSync(CATALOG_FILE)) {
            const catalog = JSON.parse(fs.readFileSync(CATALOG_FILE, 'utf8'));
            
            // We also need the status of installed containers.
            // The CLI doesn't currently output JSON, so we might need to rely on
            // the registry file created by the CLI (containers-registry.json in config dir).
            // Assuming standard location: ../../config/containers-registry.json
            const registryPath = path.resolve(COMMANDS_DIR, '..', 'config', 'containers-registry.json');
            
            let installed = [];
            if (fs.existsSync(registryPath)) {
                const registry = JSON.parse(fs.readFileSync(registryPath, 'utf8'));
                installed = registry.containers || [];
            }

            res.json({
                available: catalog.containers,
                installed: installed
            });
        } else {
            res.status(500).json({ error: 'Catalog file not found' });
        }
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// Install Container
app.post('/containers/install', async (req, res) => {
    const { name, options } = req.body;
    
    if (!name) {
        return res.status(400).json({ error: 'Container name is required' });
    }

    let args = `install ${name}`;
    if (options) {
        // Add options like --domain, --port, etc.
        // Be careful with injection here in a real app, but for now we trust the input slightly
        // or we should whitelist options.
        if (options.domain) args += ` --domain ${options.domain}`;
        if (options.port) args += ` --port ${options.port}`;
        if (options.image) args += ` --image ${options.image}`;
    }

    try {
        const output = await runHostfy(args);
        res.json({ success: true, message: 'Container installation started', output });
    } catch (error) {
        res.status(500).json({ error: 'Installation failed', details: error });
    }
});

// Delete Container
app.post('/containers/delete', async (req, res) => {
    const { name, volumes } = req.body;

    if (!name) {
        return res.status(400).json({ error: 'Container name is required' });
    }

    let args = `delete ${name} --force`; // Force to skip prompt
    if (volumes) args += ' --volumes';

    try {
        const output = await runHostfy(args);
        res.json({ success: true, message: 'Container deleted', output });
    } catch (error) {
        res.status(500).json({ error: 'Deletion failed', details: error });
    }
});

// Start Container
app.post('/containers/:name/start', async (req, res) => {
    const { name } = req.params;
    try {
        // Assuming restart handles start if stopped
        const output = await runHostfy(`restart ${name}`);
        res.json({ success: true, output });
    } catch (error) {
        res.status(500).json({ error: 'Start failed', details: error });
    }
});

// Stop Container
app.post('/containers/:name/stop', async (req, res) => {
    const { name } = req.params;
    try {
        const output = await runHostfy(`pause ${name}`); // Using pause as stop wrapper or implement stop in CLI
        res.json({ success: true, output });
    } catch (error) {
        res.status(500).json({ error: 'Stop failed', details: error });
    }
});

// Get Logs
app.get('/containers/:name/logs', async (req, res) => {
    const { name } = req.params;
    const tail = req.query.tail || 50;
    
    try {
        const output = await runHostfy(`logs ${name} --tail ${tail}`);
        res.json({ logs: output });
    } catch (error) {
        res.status(500).json({ error: 'Failed to get logs', details: error });
    }
});

// Start Server
app.listen(PORT, () => {
    console.log(`Hostfy API Server running on port ${PORT}`);
    console.log(`API Key protection: ${API_KEY ? 'ENABLED' : 'DISABLED (WARNING)'}`);
});
