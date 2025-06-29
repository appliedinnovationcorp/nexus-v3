const axios = require('axios');
const { Pool } = require('pg');
const Redis = require('redis');
const { logger, qualityGateExecutions, qualityGateDuration } = require('../index');

class QualityGateService {
    constructor() {
        this.db = new Pool({
            connectionString: process.env.POSTGRES_URL
        });
        
        this.redis = Redis.createClient({
            url: process.env.REDIS_URL
        });
        
        this.redis.connect();
        
        this.services = {
            sonarqube: process.env.SONARQUBE_URL,
            zap: process.env.ZAP_URL,
            trivy: process.env.TRIVY_URL,
            pa11y: process.env.PA11Y_URL,
            lighthouse: process.env.LIGHTHOUSE_URL,
            eslint: process.env.ESLINT_URL
        };
    }

    async executeGates(project, gates, config = {}) {
        const startTime = Date.now();
        const results = [];
        
        try {
            logger.info(`Executing quality gates for project: ${project}`, { gates });
            
            for (const gate of gates) {
                const gateResult = await this.executeGate(project, gate, config);
                results.push(gateResult);
                
                // Record metrics
                qualityGateExecutions.inc({
                    project,
                    gate_type: gate.type,
                    status: gateResult.passed ? 'passed' : 'failed'
                });
                
                qualityGateDuration.observe(
                    { project, gate_type: gate.type },
                    (Date.now() - startTime) / 1000
                );
            }
            
            // Store execution results
            await this.storeExecution(project, results, Date.now() - startTime, config);
            
            return results;
        } catch (error) {
            logger.error('Quality gate execution failed', { project, error: error.message });
            throw error;
        }
    }

    async executeGate(project, gate, config) {
        const gateConfig = await this.getGateConfig(project, gate.type);
        
        switch (gate.type) {
            case 'code_quality':
                return await this.executeCodeQualityGate(project, gateConfig, config);
            case 'security_scan':
                return await this.executeSecurityGate(project, gateConfig, config);
            case 'performance':
                return await this.executePerformanceGate(project, gateConfig, config);
            case 'accessibility':
                return await this.executeAccessibilityGate(project, gateConfig, config);
            case 'lint':
                return await this.executeLintGate(project, gateConfig, config);
            default:
                throw new Error(`Unknown gate type: ${gate.type}`);
        }
    }

    async executeCodeQualityGate(project, config, options) {
        try {
            logger.info('Executing code quality gate', { project });
            
            // Trigger SonarQube analysis
            const analysisResponse = await axios.post(
                `${this.services.sonarqube}/api/project_analyses/create_event`,
                {
                    project: project,
                    name: `Quality Gate - ${new Date().toISOString()}`
                }
            );
            
            // Get quality gate status
            const qualityGateResponse = await axios.get(
                `${this.services.sonarqube}/api/qualitygates/project_status`,
                {
                    params: { projectKey: project }
                }
            );
            
            const qualityGateStatus = qualityGateResponse.data.projectStatus;
            
            // Get detailed metrics
            const metricsResponse = await axios.get(
                `${this.services.sonarqube}/api/measures/component`,
                {
                    params: {
                        component: project,
                        metricKeys: 'coverage,duplicated_lines_density,maintainability_rating,reliability_rating,security_rating,bugs,vulnerabilities,code_smells,ncloc'
                    }
                }
            );
            
            const metrics = {};
            metricsResponse.data.component.measures.forEach(measure => {
                metrics[measure.metric] = measure.value;
            });
            
            const thresholds = config.thresholds;
            const violations = [];
            
            // Check thresholds
            if (parseFloat(metrics.coverage) < thresholds.coverage) {
                violations.push(`Coverage ${metrics.coverage}% below threshold ${thresholds.coverage}%`);
            }
            
            if (parseFloat(metrics.duplicated_lines_density) > thresholds.duplicated_lines_density) {
                violations.push(`Duplicated lines ${metrics.duplicated_lines_density}% above threshold ${thresholds.duplicated_lines_density}%`);
            }
            
            return {
                type: 'code_quality',
                passed: qualityGateStatus.status === 'OK' && violations.length === 0,
                status: qualityGateStatus.status,
                metrics,
                violations,
                details: {
                    sonarqube_status: qualityGateStatus,
                    analysis_id: analysisResponse.data?.analysisId
                }
            };
        } catch (error) {
            logger.error('Code quality gate failed', { project, error: error.message });
            return {
                type: 'code_quality',
                passed: false,
                error: error.message,
                metrics: {},
                violations: ['Code quality analysis failed']
            };
        }
    }

    async executeSecurityGate(project, config, options) {
        try {
            logger.info('Executing security gate', { project });
            
            const results = {
                zap: null,
                trivy: null
            };
            
            // OWASP ZAP Security Scan
            try {
                const zapScanResponse = await axios.post(
                    `${this.services.zap}/JSON/ascan/action/scan/`,
                    null,
                    {
                        params: {
                            url: options.target_url || 'http://localhost:3000',
                            recurse: true,
                            inScopeOnly: false
                        }
                    }
                );
                
                // Wait for scan completion (simplified)
                await new Promise(resolve => setTimeout(resolve, 30000));
                
                const zapResultsResponse = await axios.get(
                    `${this.services.zap}/JSON/core/view/alerts/`
                );
                
                results.zap = zapResultsResponse.data.alerts;
            } catch (zapError) {
                logger.warn('ZAP scan failed', { error: zapError.message });
                results.zap = { error: zapError.message };
            }
            
            // Trivy Security Scan
            try {
                const trivyResponse = await axios.post(
                    `${this.services.trivy}/scan`,
                    {
                        target: options.image || 'nexus-v3:latest',
                        format: 'json'
                    }
                );
                
                results.trivy = trivyResponse.data;
            } catch (trivyError) {
                logger.warn('Trivy scan failed', { error: trivyError.message });
                results.trivy = { error: trivyError.message };
            }
            
            // Analyze results against thresholds
            const thresholds = config.thresholds;
            const violations = [];
            
            let highVulns = 0, mediumVulns = 0, lowVulns = 0;
            
            if (results.zap && Array.isArray(results.zap)) {
                results.zap.forEach(alert => {
                    switch (alert.risk) {
                        case 'High': highVulns++; break;
                        case 'Medium': mediumVulns++; break;
                        case 'Low': lowVulns++; break;
                    }
                });
            }
            
            if (results.trivy && results.trivy.Results) {
                results.trivy.Results.forEach(result => {
                    if (result.Vulnerabilities) {
                        result.Vulnerabilities.forEach(vuln => {
                            switch (vuln.Severity) {
                                case 'HIGH':
                                case 'CRITICAL': highVulns++; break;
                                case 'MEDIUM': mediumVulns++; break;
                                case 'LOW': lowVulns++; break;
                            }
                        });
                    }
                });
            }
            
            if (highVulns > thresholds.high_vulnerabilities) {
                violations.push(`High vulnerabilities: ${highVulns} > ${thresholds.high_vulnerabilities}`);
            }
            
            if (mediumVulns > thresholds.medium_vulnerabilities) {
                violations.push(`Medium vulnerabilities: ${mediumVulns} > ${thresholds.medium_vulnerabilities}`);
            }
            
            if (lowVulns > thresholds.low_vulnerabilities) {
                violations.push(`Low vulnerabilities: ${lowVulns} > ${thresholds.low_vulnerabilities}`);
            }
            
            return {
                type: 'security_scan',
                passed: violations.length === 0,
                metrics: {
                    high_vulnerabilities: highVulns,
                    medium_vulnerabilities: mediumVulns,
                    low_vulnerabilities: lowVulns
                },
                violations,
                details: results
            };
        } catch (error) {
            logger.error('Security gate failed', { project, error: error.message });
            return {
                type: 'security_scan',
                passed: false,
                error: error.message,
                violations: ['Security scan failed']
            };
        }
    }

    async executePerformanceGate(project, config, options) {
        try {
            logger.info('Executing performance gate', { project });
            
            // Trigger Lighthouse CI analysis
            const lighthouseResponse = await axios.post(
                `${this.services.lighthouse}/v1/projects/${project}/builds`,
                {
                    projectId: project,
                    lifecycle: 'lhci',
                    hash: options.commit_hash || 'latest',
                    branch: options.branch || 'main',
                    externalBuildUrl: options.build_url
                }
            );
            
            const buildId = lighthouseResponse.data.id;
            
            // Wait for analysis completion
            await new Promise(resolve => setTimeout(resolve, 60000));
            
            // Get results
            const resultsResponse = await axios.get(
                `${this.services.lighthouse}/v1/projects/${project}/builds/${buildId}/runs`
            );
            
            const runs = resultsResponse.data;
            const latestRun = runs[runs.length - 1];
            
            if (!latestRun || !latestRun.lhr) {
                throw new Error('No Lighthouse results available');
            }
            
            const categories = latestRun.lhr.categories;
            const thresholds = config.thresholds;
            const violations = [];
            
            const scores = {
                performance: Math.round(categories.performance.score * 100),
                accessibility: Math.round(categories.accessibility.score * 100),
                'best-practices': Math.round(categories['best-practices'].score * 100),
                seo: Math.round(categories.seo.score * 100)
            };
            
            if (scores.performance < thresholds.performance_score) {
                violations.push(`Performance score ${scores.performance} below threshold ${thresholds.performance_score}`);
            }
            
            if (scores.accessibility < thresholds.accessibility_score) {
                violations.push(`Accessibility score ${scores.accessibility} below threshold ${thresholds.accessibility_score}`);
            }
            
            if (scores['best-practices'] < thresholds.best_practices_score) {
                violations.push(`Best practices score ${scores['best-practices']} below threshold ${thresholds.best_practices_score}`);
            }
            
            if (scores.seo < thresholds.seo_score) {
                violations.push(`SEO score ${scores.seo} below threshold ${thresholds.seo_score}`);
            }
            
            return {
                type: 'performance',
                passed: violations.length === 0,
                metrics: scores,
                violations,
                details: {
                    lighthouse_run_id: latestRun.id,
                    build_id: buildId,
                    categories: categories
                }
            };
        } catch (error) {
            logger.error('Performance gate failed', { project, error: error.message });
            return {
                type: 'performance',
                passed: false,
                error: error.message,
                violations: ['Performance analysis failed']
            };
        }
    }

    async executeAccessibilityGate(project, config, options) {
        try {
            logger.info('Executing accessibility gate', { project });
            
            // Trigger Pa11y scan
            const pa11yResponse = await axios.post(
                `${this.services.pa11y}/api/tasks`,
                {
                    name: `${project} - Accessibility Scan`,
                    url: options.target_url || 'http://localhost:3000',
                    standard: 'WCAG2AA'
                }
            );
            
            const taskId = pa11yResponse.data.id;
            
            // Wait for scan completion
            await new Promise(resolve => setTimeout(resolve, 30000));
            
            // Get results
            const resultsResponse = await axios.get(
                `${this.services.pa11y}/api/tasks/${taskId}/results`
            );
            
            const results = resultsResponse.data;
            const thresholds = config.thresholds;
            const violations = [];
            
            let errors = 0, warnings = 0, notices = 0;
            
            results.forEach(result => {
                switch (result.type) {
                    case 'error': errors++; break;
                    case 'warning': warnings++; break;
                    case 'notice': notices++; break;
                }
            });
            
            if (errors > thresholds.errors) {
                violations.push(`Accessibility errors: ${errors} > ${thresholds.errors}`);
            }
            
            if (warnings > thresholds.warnings) {
                violations.push(`Accessibility warnings: ${warnings} > ${thresholds.warnings}`);
            }
            
            if (notices > thresholds.notices) {
                violations.push(`Accessibility notices: ${notices} > ${thresholds.notices}`);
            }
            
            return {
                type: 'accessibility',
                passed: violations.length === 0,
                metrics: {
                    errors,
                    warnings,
                    notices
                },
                violations,
                details: {
                    task_id: taskId,
                    results: results
                }
            };
        } catch (error) {
            logger.error('Accessibility gate failed', { project, error: error.message });
            return {
                type: 'accessibility',
                passed: false,
                error: error.message,
                violations: ['Accessibility scan failed']
            };
        }
    }

    async executeLintGate(project, config, options) {
        try {
            logger.info('Executing lint gate', { project });
            
            const files = options.files || ['**/*.{js,ts,jsx,tsx}'];
            
            const lintResponse = await axios.post(
                `${this.services.eslint}/lint`,
                {
                    files,
                    config: options.eslint_config
                }
            );
            
            const results = lintResponse.data;
            let errorCount = 0, warningCount = 0;
            
            results.forEach(result => {
                errorCount += result.errorCount;
                warningCount += result.warningCount;
            });
            
            const thresholds = config.thresholds || { errors: 0, warnings: 10 };
            const violations = [];
            
            if (errorCount > thresholds.errors) {
                violations.push(`ESLint errors: ${errorCount} > ${thresholds.errors}`);
            }
            
            if (warningCount > thresholds.warnings) {
                violations.push(`ESLint warnings: ${warningCount} > ${thresholds.warnings}`);
            }
            
            return {
                type: 'lint',
                passed: violations.length === 0,
                metrics: {
                    errors: errorCount,
                    warnings: warningCount
                },
                violations,
                details: results
            };
        } catch (error) {
            logger.error('Lint gate failed', { project, error: error.message });
            return {
                type: 'lint',
                passed: false,
                error: error.message,
                violations: ['Lint analysis failed']
            };
        }
    }

    async getGateConfig(project, gateType) {
        const cacheKey = `config:${project}:${gateType}`;
        
        try {
            const cached = await this.redis.get(cacheKey);
            if (cached) {
                return JSON.parse(cached);
            }
        } catch (error) {
            logger.warn('Redis cache error', { error: error.message });
        }
        
        const result = await this.db.query(
            'SELECT configuration, thresholds FROM quality_gate_configs WHERE project_id = (SELECT id FROM projects WHERE name = $1) AND gate_type = $2 AND is_active = true',
            [project, gateType]
        );
        
        if (result.rows.length === 0) {
            throw new Error(`No configuration found for ${gateType} gate in project ${project}`);
        }
        
        const config = {
            ...result.rows[0].configuration,
            thresholds: result.rows[0].thresholds
        };
        
        try {
            await this.redis.setEx(cacheKey, 300, JSON.stringify(config));
        } catch (error) {
            logger.warn('Redis cache set error', { error: error.message });
        }
        
        return config;
    }

    async storeExecution(project, results, duration, config) {
        const client = await this.db.connect();
        
        try {
            await client.query('BEGIN');
            
            const projectResult = await client.query(
                'SELECT id FROM projects WHERE name = $1',
                [project]
            );
            
            if (projectResult.rows.length === 0) {
                throw new Error(`Project ${project} not found`);
            }
            
            const projectId = projectResult.rows[0].id;
            
            for (const result of results) {
                const executionResult = await client.query(
                    'INSERT INTO quality_gate_executions (project_id, gate_type, status, results, metrics, duration_ms, commit_hash, branch) VALUES ($1, $2, $3, $4, $5, $6, $7, $8) RETURNING id',
                    [
                        projectId,
                        result.type,
                        result.passed ? 'PASSED' : 'FAILED',
                        JSON.stringify(result),
                        JSON.stringify(result.metrics || {}),
                        duration,
                        config.commit_hash,
                        config.branch
                    ]
                );
                
                const executionId = executionResult.rows[0].id;
                
                // Store individual metrics
                if (result.metrics) {
                    for (const [metricName, value] of Object.entries(result.metrics)) {
                        await client.query(
                            'INSERT INTO quality_metrics (project_id, metric_type, metric_name, value, status, execution_id) VALUES ($1, $2, $3, $4, $5, $6)',
                            [
                                projectId,
                                result.type,
                                metricName,
                                parseFloat(value) || 0,
                                result.passed ? 'PASSED' : 'FAILED',
                                executionId
                            ]
                        );
                    }
                }
            }
            
            await client.query('COMMIT');
        } catch (error) {
            await client.query('ROLLBACK');
            throw error;
        } finally {
            client.release();
        }
    }

    async getHistory(project, limit = 50, offset = 0) {
        const result = await this.db.query(
            `SELECT qge.*, p.name as project_name 
             FROM quality_gate_executions qge 
             JOIN projects p ON qge.project_id = p.id 
             WHERE p.name = $1 
             ORDER BY qge.executed_at DESC 
             LIMIT $2 OFFSET $3`,
            [project, limit, offset]
        );
        
        return result.rows;
    }

    async getConfig(project) {
        const result = await this.db.query(
            `SELECT qgc.*, p.name as project_name 
             FROM quality_gate_configs qgc 
             JOIN projects p ON qgc.project_id = p.id 
             WHERE p.name = $1 AND qgc.is_active = true`,
            [project]
        );
        
        return result.rows;
    }

    async updateConfig(project, config) {
        const client = await this.db.connect();
        
        try {
            await client.query('BEGIN');
            
            const projectResult = await client.query(
                'SELECT id FROM projects WHERE name = $1',
                [project]
            );
            
            if (projectResult.rows.length === 0) {
                throw new Error(`Project ${project} not found`);
            }
            
            const projectId = projectResult.rows[0].id;
            
            // Deactivate existing configs
            await client.query(
                'UPDATE quality_gate_configs SET is_active = false WHERE project_id = $1',
                [projectId]
            );
            
            // Insert new configs
            for (const gateConfig of config.gates) {
                await client.query(
                    'INSERT INTO quality_gate_configs (project_id, gate_type, configuration, thresholds, is_active) VALUES ($1, $2, $3, $4, true)',
                    [
                        projectId,
                        gateConfig.type,
                        JSON.stringify(gateConfig.configuration),
                        JSON.stringify(gateConfig.thresholds)
                    ]
                );
            }
            
            await client.query('COMMIT');
            
            // Clear cache
            const cachePattern = `config:${project}:*`;
            try {
                const keys = await this.redis.keys(cachePattern);
                if (keys.length > 0) {
                    await this.redis.del(keys);
                }
            } catch (error) {
                logger.warn('Cache clear error', { error: error.message });
            }
            
        } catch (error) {
            await client.query('ROLLBACK');
            throw error;
        } finally {
            client.release();
        }
    }
}

module.exports = QualityGateService;
