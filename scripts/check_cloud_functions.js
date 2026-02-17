const sdk = require('node-appwrite');

// Configuration
const CONFIG = {
    endpoint: process.env.APPWRITE_ENDPOINT || 'https://fra.cloud.appwrite.io/v1',
    projectId: process.env.APPWRITE_PROJECT_ID || '6941cdb400050e7249d5',
    apiKey: process.env.APPWRITE_API_KEY,
};

const EXPECTED_FUNCTIONS = [
    {
        id: 'escalation-timer',
        name: 'Escalation Timer',
        schedule: '*/5 * * * *',
        enabled: true,
    },
    {
        id: 'verification-request',
        name: 'Verification Request',
        events: ['databases.*.collections.reports.documents.*.create'],
        enabled: true,
    },
    {
        id: 'statistics-aggregation',
        name: 'Statistics Aggregation',
        schedule: '0 0 * * *',
        enabled: true,
    },
    {
        id: 'send-email',
        name: 'Send Email',
        enabled: true,
    },
];

async function checkCloudFunctions() {
    if (!CONFIG.apiKey) {
        console.error('❌ Error: APPWRITE_API_KEY environment variable is required');
        console.log('\nUsage:');
        console.log('  APPWRITE_API_KEY=your_key node scripts/check_cloud_functions.js');
        process.exit(1);
    }

    console.log('🔍 CRADI Mobile - Cloud Functions Health Check\n');
    console.log(`Project ID: ${CONFIG.projectId}`);
    console.log(`Endpoint: ${CONFIG.endpoint}\n`);

    const client = new sdk.Client()
        .setEndpoint(CONFIG.endpoint)
        .setProject(CONFIG.projectId)
        .setKey(CONFIG.apiKey);

    const functions = new sdk.Functions(client);

    const results = {
        timestamp: new Date().toISOString(),
        projectId: CONFIG.projectId,
        functionsChecked: 0,
        functionsHealthy: 0,
        functionsFailed: 0,
        details: [],
        overallStatus: 'unknown',
    };

    for (const expectedFunc of EXPECTED_FUNCTIONS) {
        try {
            console.log(`\n📋 Checking: ${expectedFunc.name} (${expectedFunc.id})`);

            // Get function details
            const func = await functions.get(expectedFunc.id);

            const funcResult = {
                id: expectedFunc.id,
                name: expectedFunc.name,
                status: 'healthy',
                enabled: func.enabled,
                runtime: func.runtime,
                checks: {},
            };

            // Check if enabled
            if (func.enabled !== expectedFunc.enabled) {
                funcResult.checks.enabled = {
                    status: 'warning',
                    expected: expectedFunc.enabled,
                    actual: func.enabled,
                };
                console.log(`  ⚠️ Enabled: ${func.enabled} (expected: ${expectedFunc.enabled})`);
            } else {
                funcResult.checks.enabled = { status: 'pass' };
                console.log(`  ✅ Enabled: ${func.enabled}`);
            }

            // Check schedule if applicable
            if (expectedFunc.schedule) {
                if (func.schedule === expectedFunc.schedule) {
                    funcResult.checks.schedule = { status: 'pass', value: func.schedule };
                    console.log(`  ✅ Schedule: ${func.schedule}`);
                } else {
                    funcResult.checks.schedule = {
                        status: 'warning',
                        expected: expectedFunc.schedule,
                        actual: func.schedule,
                    };
                    console.log(`  ⚠️ Schedule: ${func.schedule} (expected: ${expectedFunc.schedule})`);
                }
            }

            // Check events if applicable
            if (expectedFunc.events) {
                const hasAllEvents = expectedFunc.events.every(event =>
                    func.events?.includes(event)
                );

                if (hasAllEvents) {
                    funcResult.checks.events = { status: 'pass', value: func.events };
                    console.log(`  ✅ Events: ${func.events?.join(', ')}`);
                } else {
                    funcResult.checks.events = {
                        status: 'warning',
                        expected: expectedFunc.events,
                        actual: func.events,
                    };
                    console.log(`  ⚠️ Events mismatch`);
                }
            }

            // Get recent executions
            try {
                const executions = await functions.listExecutions(expectedFunc.id, [
                    sdk.Query.limit(10),
                    sdk.Query.orderDesc('$createdAt'),
                ]);

                funcResult.executions = {
                    total: executions.total,
                    recent: executions.executions.length,
                };

                if (executions.executions.length > 0) {
                    const recentExecution = executions.executions[0];
                    const errors = executions.executions.filter(e => e.status === 'failed').length;
                    const errorRate = executions.executions.length > 0
                        ? (errors / executions.executions.length) * 100
                        : 0;

                    funcResult.executions.lastRun = recentExecution.$createdAt;
                    funcResult.executions.lastStatus = recentExecution.status;
                    funcResult.executions.errorRate = `${errorRate.toFixed(1)}%`;
                    funcResult.executions.errors = errors;

                    console.log(`  📊 Last run: ${recentExecution.$createdAt}`);
                    console.log(`  📊 Last status: ${recentExecution.status}`);
                    console.log(`  📊 Error rate: ${errorRate.toFixed(1)}% (${errors}/${executions.executions.length})`);

                    if (errorRate > 50) {
                        funcResult.status = 'unhealthy';
                        funcResult.checks.errorRate = {
                            status: 'fail',
                            value: errorRate,
                            message: 'High error rate',
                        };
                        console.log(`  ❌ High error rate: ${errorRate.toFixed(1)}%`);
                    } else if (errorRate > 10) {
                        funcResult.checks.errorRate = {
                            status: 'warning',
                            value: errorRate,
                        };
                        console.log(`  ⚠️ Moderate error rate: ${errorRate.toFixed(1)}%`);
                    } else {
                        funcResult.checks.errorRate = { status: 'pass', value: errorRate };
                        console.log(`  ✅ Low error rate: ${errorRate.toFixed(1)}%`);
                    }

                    // Check if recent execution had errors
                    if (recentExecution.status === 'failed') {
                        console.log(`  ⚠️ Most recent execution failed`);
                        if (recentExecution.stderr) {
                            console.log(`  Error: ${recentExecution.stderr.substring(0, 200)}...`);
                        }
                    }
                } else {
                    console.log(`  ℹ️ No recent executions found`);
                    funcResult.executions.message = 'No recent executions';
                }
            } catch (execError) {
                console.log(`  ⚠️ Could not fetch executions: ${execError.message}`);
                funcResult.executions = { error: execError.message };
            }

            results.functionsChecked++;
            if (funcResult.status === 'healthy') {
                results.functionsHealthy++;
                console.log(`  ✅ Overall: Healthy`);
            } else {
                results.functionsFailed++;
                console.log(`  ❌ Overall: Unhealthy`);
            }

            results.details.push(funcResult);
        } catch (error) {
            console.log(`  ❌ Error checking function: ${error.message}`);
            if (error.code === 404) {
                console.log(`  ⚠️ Function not found - may need to be deployed`);
            }

            results.functionsChecked++;
            results.functionsFailed++;
            results.details.push({
                id: expectedFunc.id,
                name: expectedFunc.name,
                status: 'error',
                error: error.message,
                code: error.code,
            });
        }
    }

    // Determine overall status
    if (results.functionsFailed === 0) {
        results.overallStatus = 'healthy';
    } else if (results.functionsFailed < results.functionsChecked) {
        results.overallStatus = 'degraded';
    } else {
        results.overallStatus = 'critical';
    }

    // Print summary
    console.log('\n' + '='.repeat(60));
    console.log('📊 HEALTH CHECK SUMMARY');
    console.log('='.repeat(60));
    console.log(`Overall Status: ${results.overallStatus.toUpperCase()}`);
    console.log(`Functions Checked: ${results.functionsChecked}`);
    console.log(`Healthy: ${results.functionsHealthy}`);
    console.log(`Unhealthy/Error: ${results.functionsFailed}`);
    console.log('='.repeat(60));

    console.log('\n💡 Recommendations:');
    if (results.overallStatus === 'healthy') {
        console.log('  ✅ All functions are operating normally');
    } else {
        console.log('  ⚠️ Some functions require attention');
        console.log('  → Check Appwrite Console for detailed error logs');
        console.log('  → Verify function environment variables are set');
        console.log('  → Ensure all dependencies are installed');
    }

    console.log('\n');

    // Exit with appropriate code
    if (results.overallStatus === 'critical') {
        process.exit(1);
    }
}

checkCloudFunctions().catch((error) => {
    console.error('\n❌ Fatal error:', error.message);
    process.exit(1);
});
