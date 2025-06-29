import { exec } from 'child_process';
import { promisify } from 'util';
import fs from 'fs/promises';
import path from 'path';
import axios from 'axios';
import { logger } from '../utils/logger';

const execAsync = promisify(exec);

export interface DependencyVulnerability {
  id: string;
  title: string;
  description: string;
  severity: 'critical' | 'high' | 'medium' | 'low';
  cvss: number;
  cve?: string[];
  cwe?: string[];
  package: {
    name: string;
    version: string;
    ecosystem: string;
  };
  fixedIn?: string;
  patchedVersions?: string[];
  vulnerableVersions?: string;
  references: string[];
  publishedDate?: string;
  modifiedDate?: string;
}

export interface ScanResult {
  scanId: string;
  timestamp: string;
  projectPath: string;
  summary: {
    total: number;
    critical: number;
    high: number;
    medium: number;
    low: number;
  };
  vulnerabilities: DependencyVulnerability[];
  dependencies: {
    total: number;
    direct: number;
    transitive: number;
  };
  scanDuration: number;
}

export interface ScannerConfig {
  snykToken?: string;
  owaspDcPath?: string;
  enabledScanners: ('npm-audit' | 'snyk' | 'owasp-dc' | 'yarn-audit' | 'retire-js')[];
  outputDir: string;
  failOnVulnerabilities: boolean;
  severityThreshold: 'critical' | 'high' | 'medium' | 'low';
}

export class DependencyScanner {
  private config: ScannerConfig;

  constructor(config: ScannerConfig) {
    this.config = config;
  }

  async scanProject(projectPath: string): Promise<ScanResult> {
    const startTime = Date.now();
    const scanId = `scan_${Date.now()}`;
    
    logger.info(`Starting dependency scan for project: ${projectPath}`);

    try {
      const allVulnerabilities: DependencyVulnerability[] = [];
      let totalDependencies = 0;
      let directDependencies = 0;

      // Run enabled scanners
      for (const scanner of this.config.enabledScanners) {
        try {
          logger.info(`Running ${scanner} scanner...`);
          const result = await this.runScanner(scanner, projectPath);
          allVulnerabilities.push(...result.vulnerabilities);
          
          if (result.dependencies) {
            totalDependencies = Math.max(totalDependencies, result.dependencies.total);
            directDependencies = Math.max(directDependencies, result.dependencies.direct);
          }
        } catch (error) {
          logger.error(`Scanner ${scanner} failed:`, error);
        }
      }

      // Deduplicate vulnerabilities
      const uniqueVulnerabilities = this.deduplicateVulnerabilities(allVulnerabilities);

      // Calculate summary
      const summary = this.calculateSummary(uniqueVulnerabilities);

      const scanResult: ScanResult = {
        scanId,
        timestamp: new Date().toISOString(),
        projectPath,
        summary,
        vulnerabilities: uniqueVulnerabilities,
        dependencies: {
          total: totalDependencies,
          direct: directDependencies,
          transitive: totalDependencies - directDependencies
        },
        scanDuration: Date.now() - startTime
      };

      // Save results
      await this.saveResults(scanResult);

      logger.info(`Dependency scan completed. Found ${summary.total} vulnerabilities`);
      return scanResult;

    } catch (error) {
      logger.error('Dependency scan failed:', error);
      throw new Error(`Dependency scan failed: ${error}`);
    }
  }

  private async runScanner(scanner: string, projectPath: string): Promise<{
    vulnerabilities: DependencyVulnerability[];
    dependencies?: { total: number; direct: number };
  }> {
    switch (scanner) {
      case 'npm-audit':
        return this.runNpmAudit(projectPath);
      case 'yarn-audit':
        return this.runYarnAudit(projectPath);
      case 'snyk':
        return this.runSnyk(projectPath);
      case 'owasp-dc':
        return this.runOwaspDependencyCheck(projectPath);
      case 'retire-js':
        return this.runRetireJs(projectPath);
      default:
        throw new Error(`Unknown scanner: ${scanner}`);
    }
  }

  // NPM Audit Scanner
  private async runNpmAudit(projectPath: string): Promise<{
    vulnerabilities: DependencyVulnerability[];
    dependencies: { total: number; direct: number };
  }> {
    try {
      const { stdout } = await execAsync('npm audit --json', { cwd: projectPath });
      const auditResult = JSON.parse(stdout);

      const vulnerabilities: DependencyVulnerability[] = [];
      const advisories = auditResult.advisories || {};

      for (const [id, advisory] of Object.entries(advisories as any)) {
        vulnerabilities.push({
          id: `npm-${id}`,
          title: advisory.title,
          description: advisory.overview,
          severity: this.mapNpmSeverity(advisory.severity),
          cvss: advisory.cvss?.score || 0,
          cve: advisory.cves || [],
          cwe: advisory.cwe ? [advisory.cwe] : [],
          package: {
            name: advisory.module_name,
            version: advisory.vulnerable_versions,
            ecosystem: 'npm'
          },
          fixedIn: advisory.patched_versions,
          patchedVersions: advisory.patched_versions ? [advisory.patched_versions] : [],
          vulnerableVersions: advisory.vulnerable_versions,
          references: [advisory.url].filter(Boolean),
          publishedDate: advisory.created,
          modifiedDate: advisory.updated
        });
      }

      return {
        vulnerabilities,
        dependencies: {
          total: auditResult.metadata?.totalDependencies || 0,
          direct: auditResult.metadata?.dependencies || 0
        }
      };

    } catch (error) {
      logger.error('NPM audit failed:', error);
      return { vulnerabilities: [], dependencies: { total: 0, direct: 0 } };
    }
  }

  // Yarn Audit Scanner
  private async runYarnAudit(projectPath: string): Promise<{
    vulnerabilities: DependencyVulnerability[];
    dependencies: { total: number; direct: number };
  }> {
    try {
      const { stdout } = await execAsync('yarn audit --json', { cwd: projectPath });
      const lines = stdout.trim().split('\n');
      const vulnerabilities: DependencyVulnerability[] = [];

      for (const line of lines) {
        try {
          const data = JSON.parse(line);
          if (data.type === 'auditAdvisory') {
            const advisory = data.data.advisory;
            vulnerabilities.push({
              id: `yarn-${advisory.id}`,
              title: advisory.title,
              description: advisory.overview,
              severity: this.mapYarnSeverity(advisory.severity),
              cvss: advisory.cvss || 0,
              cve: advisory.cves || [],
              cwe: advisory.cwe ? [advisory.cwe] : [],
              package: {
                name: advisory.module_name,
                version: advisory.vulnerable_versions,
                ecosystem: 'npm'
              },
              fixedIn: advisory.patched_versions,
              patchedVersions: advisory.patched_versions ? [advisory.patched_versions] : [],
              vulnerableVersions: advisory.vulnerable_versions,
              references: [advisory.url].filter(Boolean),
              publishedDate: advisory.created,
              modifiedDate: advisory.updated
            });
          }
        } catch (parseError) {
          // Skip invalid JSON lines
        }
      }

      return { vulnerabilities, dependencies: { total: 0, direct: 0 } };

    } catch (error) {
      logger.error('Yarn audit failed:', error);
      return { vulnerabilities: [], dependencies: { total: 0, direct: 0 } };
    }
  }

  // Snyk Scanner
  private async runSnyk(projectPath: string): Promise<{
    vulnerabilities: DependencyVulnerability[];
    dependencies: { total: number; direct: number };
  }> {
    if (!this.config.snykToken) {
      logger.warn('Snyk token not provided, skipping Snyk scan');
      return { vulnerabilities: [], dependencies: { total: 0, direct: 0 } };
    }

    try {
      // Authenticate with Snyk
      await execAsync(`snyk auth ${this.config.snykToken}`);

      // Run Snyk test
      const { stdout } = await execAsync('snyk test --json', { cwd: projectPath });
      const snykResult = JSON.parse(stdout);

      const vulnerabilities: DependencyVulnerability[] = [];

      if (snykResult.vulnerabilities) {
        for (const vuln of snykResult.vulnerabilities) {
          vulnerabilities.push({
            id: `snyk-${vuln.id}`,
            title: vuln.title,
            description: vuln.description,
            severity: this.mapSnykSeverity(vuln.severity),
            cvss: vuln.cvssScore || 0,
            cve: vuln.identifiers?.CVE || [],
            cwe: vuln.identifiers?.CWE || [],
            package: {
              name: vuln.packageName,
              version: vuln.version,
              ecosystem: 'npm'
            },
            fixedIn: vuln.fixedIn?.[0],
            patchedVersions: vuln.fixedIn || [],
            vulnerableVersions: vuln.version,
            references: [vuln.url, ...(vuln.references || [])].filter(Boolean),
            publishedDate: vuln.publicationTime,
            modifiedDate: vuln.modificationTime
          });
        }
      }

      return {
        vulnerabilities,
        dependencies: {
          total: snykResult.dependencyCount || 0,
          direct: 0 // Snyk doesn't provide this info directly
        }
      };

    } catch (error) {
      logger.error('Snyk scan failed:', error);
      return { vulnerabilities: [], dependencies: { total: 0, direct: 0 } };
    }
  }

  // OWASP Dependency Check Scanner
  private async runOwaspDependencyCheck(projectPath: string): Promise<{
    vulnerabilities: DependencyVulnerability[];
    dependencies: { total: number; direct: number };
  }> {
    try {
      const outputDir = path.join(this.config.outputDir, 'owasp-dc');
      await fs.mkdir(outputDir, { recursive: true });

      const command = `dependency-check --project "Security Scan" --scan "${projectPath}" --format JSON --out "${outputDir}"`;
      await execAsync(command);

      // Read the JSON report
      const reportPath = path.join(outputDir, 'dependency-check-report.json');
      const reportContent = await fs.readFile(reportPath, 'utf-8');
      const report = JSON.parse(reportContent);

      const vulnerabilities: DependencyVulnerability[] = [];

      if (report.dependencies) {
        for (const dependency of report.dependencies) {
          if (dependency.vulnerabilities) {
            for (const vuln of dependency.vulnerabilities) {
              vulnerabilities.push({
                id: `owasp-${vuln.name}`,
                title: vuln.name,
                description: vuln.description || '',
                severity: this.mapOwaspSeverity(vuln.severity),
                cvss: vuln.cvssv3?.baseScore || vuln.cvssv2?.score || 0,
                cve: [vuln.name].filter(name => name.startsWith('CVE-')),
                cwe: vuln.cwe ? [vuln.cwe] : [],
                package: {
                  name: dependency.fileName,
                  version: dependency.version || 'unknown',
                  ecosystem: this.detectEcosystem(dependency.fileName)
                },
                references: vuln.references?.map((ref: any) => ref.url).filter(Boolean) || [],
                publishedDate: vuln.publishedDate,
                modifiedDate: vuln.updatedDate
              });
            }
          }
        }
      }

      return { vulnerabilities, dependencies: { total: 0, direct: 0 } };

    } catch (error) {
      logger.error('OWASP Dependency Check failed:', error);
      return { vulnerabilities: [], dependencies: { total: 0, direct: 0 } };
    }
  }

  // Retire.js Scanner
  private async runRetireJs(projectPath: string): Promise<{
    vulnerabilities: DependencyVulnerability[];
    dependencies: { total: number; direct: number };
  }> {
    try {
      const { stdout } = await execAsync('retire --outputformat json', { cwd: projectPath });
      const retireResult = JSON.parse(stdout);

      const vulnerabilities: DependencyVulnerability[] = [];

      if (retireResult.data) {
        for (const result of retireResult.data) {
          if (result.results) {
            for (const vuln of result.results) {
              vulnerabilities.push({
                id: `retire-${vuln.component}-${vuln.version}`,
                title: `${vuln.component} ${vuln.version} vulnerability`,
                description: vuln.vulnerabilities?.[0]?.info?.join(' ') || '',
                severity: this.mapRetireSeverity(vuln.vulnerabilities?.[0]?.severity),
                cvss: 0,
                cve: vuln.vulnerabilities?.[0]?.identifiers?.CVE || [],
                package: {
                  name: vuln.component,
                  version: vuln.version,
                  ecosystem: 'javascript'
                },
                references: vuln.vulnerabilities?.[0]?.info || [],
                vulnerableVersions: vuln.version
              });
            }
          }
        }
      }

      return { vulnerabilities, dependencies: { total: 0, direct: 0 } };

    } catch (error) {
      logger.error('Retire.js scan failed:', error);
      return { vulnerabilities: [], dependencies: { total: 0, direct: 0 } };
    }
  }

  // Utility methods
  private deduplicateVulnerabilities(vulnerabilities: DependencyVulnerability[]): DependencyVulnerability[] {
    const seen = new Set<string>();
    const unique: DependencyVulnerability[] = [];

    for (const vuln of vulnerabilities) {
      const key = `${vuln.package.name}-${vuln.package.version}-${vuln.title}`;
      if (!seen.has(key)) {
        seen.add(key);
        unique.push(vuln);
      }
    }

    return unique;
  }

  private calculateSummary(vulnerabilities: DependencyVulnerability[]): {
    total: number;
    critical: number;
    high: number;
    medium: number;
    low: number;
  } {
    return {
      total: vulnerabilities.length,
      critical: vulnerabilities.filter(v => v.severity === 'critical').length,
      high: vulnerabilities.filter(v => v.severity === 'high').length,
      medium: vulnerabilities.filter(v => v.severity === 'medium').length,
      low: vulnerabilities.filter(v => v.severity === 'low').length
    };
  }

  private async saveResults(result: ScanResult): Promise<void> {
    try {
      await fs.mkdir(this.config.outputDir, { recursive: true });
      
      const filename = `dependency-scan-${result.scanId}.json`;
      const filepath = path.join(this.config.outputDir, filename);
      
      await fs.writeFile(filepath, JSON.stringify(result, null, 2));
      logger.info(`Scan results saved to: ${filepath}`);
    } catch (error) {
      logger.error('Failed to save scan results:', error);
    }
  }

  // Severity mapping functions
  private mapNpmSeverity(severity: string): 'critical' | 'high' | 'medium' | 'low' {
    switch (severity.toLowerCase()) {
      case 'critical': return 'critical';
      case 'high': return 'high';
      case 'moderate': return 'medium';
      case 'low': return 'low';
      default: return 'medium';
    }
  }

  private mapYarnSeverity(severity: string): 'critical' | 'high' | 'medium' | 'low' {
    return this.mapNpmSeverity(severity);
  }

  private mapSnykSeverity(severity: string): 'critical' | 'high' | 'medium' | 'low' {
    switch (severity.toLowerCase()) {
      case 'critical': return 'critical';
      case 'high': return 'high';
      case 'medium': return 'medium';
      case 'low': return 'low';
      default: return 'medium';
    }
  }

  private mapOwaspSeverity(severity: string): 'critical' | 'high' | 'medium' | 'low' {
    switch (severity.toUpperCase()) {
      case 'CRITICAL': return 'critical';
      case 'HIGH': return 'high';
      case 'MEDIUM': return 'medium';
      case 'LOW': return 'low';
      default: return 'medium';
    }
  }

  private mapRetireSeverity(severity?: string): 'critical' | 'high' | 'medium' | 'low' {
    if (!severity) return 'medium';
    
    switch (severity.toLowerCase()) {
      case 'critical': return 'critical';
      case 'high': return 'high';
      case 'medium': return 'medium';
      case 'low': return 'low';
      default: return 'medium';
    }
  }

  private detectEcosystem(filename: string): string {
    if (filename.includes('package.json') || filename.includes('node_modules')) {
      return 'npm';
    }
    if (filename.includes('.jar')) {
      return 'maven';
    }
    if (filename.includes('.dll') || filename.includes('.exe')) {
      return 'nuget';
    }
    return 'unknown';
  }

  // Public utility methods
  async generateReport(scanResult: ScanResult, format: 'html' | 'json' | 'csv' = 'html'): Promise<string> {
    switch (format) {
      case 'html':
        return this.generateHtmlReport(scanResult);
      case 'json':
        return JSON.stringify(scanResult, null, 2);
      case 'csv':
        return this.generateCsvReport(scanResult);
      default:
        throw new Error(`Unsupported report format: ${format}`);
    }
  }

  private generateHtmlReport(scanResult: ScanResult): string {
    const html = `
<!DOCTYPE html>
<html>
<head>
    <title>Dependency Vulnerability Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .header { background: #f5f5f5; padding: 20px; border-radius: 5px; }
        .summary { display: flex; gap: 20px; margin: 20px 0; }
        .summary-item { background: #fff; border: 1px solid #ddd; padding: 15px; border-radius: 5px; text-align: center; }
        .critical { background-color: #dc3545; color: white; }
        .high { background-color: #fd7e14; color: white; }
        .medium { background-color: #ffc107; color: black; }
        .low { background-color: #28a745; color: white; }
        .vulnerability { border: 1px solid #ddd; margin: 10px 0; padding: 15px; border-radius: 5px; }
        .vuln-header { font-weight: bold; margin-bottom: 10px; }
        .vuln-details { color: #666; }
    </style>
</head>
<body>
    <div class="header">
        <h1>Dependency Vulnerability Report</h1>
        <p><strong>Project:</strong> ${scanResult.projectPath}</p>
        <p><strong>Scan Date:</strong> ${new Date(scanResult.timestamp).toLocaleString()}</p>
        <p><strong>Scan Duration:</strong> ${(scanResult.scanDuration / 1000).toFixed(2)}s</p>
    </div>

    <div class="summary">
        <div class="summary-item critical">
            <h3>${scanResult.summary.critical}</h3>
            <p>Critical</p>
        </div>
        <div class="summary-item high">
            <h3>${scanResult.summary.high}</h3>
            <p>High</p>
        </div>
        <div class="summary-item medium">
            <h3>${scanResult.summary.medium}</h3>
            <p>Medium</p>
        </div>
        <div class="summary-item low">
            <h3>${scanResult.summary.low}</h3>
            <p>Low</p>
        </div>
    </div>

    <h2>Vulnerabilities (${scanResult.summary.total})</h2>
    ${scanResult.vulnerabilities.map(vuln => `
        <div class="vulnerability">
            <div class="vuln-header ${vuln.severity}">
                ${vuln.title} - ${vuln.severity.toUpperCase()}
            </div>
            <div class="vuln-details">
                <p><strong>Package:</strong> ${vuln.package.name}@${vuln.package.version}</p>
                <p><strong>Description:</strong> ${vuln.description}</p>
                ${vuln.fixedIn ? `<p><strong>Fixed in:</strong> ${vuln.fixedIn}</p>` : ''}
                ${vuln.cve && vuln.cve.length > 0 ? `<p><strong>CVE:</strong> ${vuln.cve.join(', ')}</p>` : ''}
                ${vuln.references.length > 0 ? `<p><strong>References:</strong> ${vuln.references.map(ref => `<a href="${ref}" target="_blank">${ref}</a>`).join(', ')}</p>` : ''}
            </div>
        </div>
    `).join('')}
</body>
</html>`;
    return html;
  }

  private generateCsvReport(scanResult: ScanResult): string {
    const headers = [
      'Package Name',
      'Package Version',
      'Vulnerability Title',
      'Severity',
      'CVSS Score',
      'CVE',
      'Description',
      'Fixed In',
      'References'
    ];

    const rows = scanResult.vulnerabilities.map(vuln => [
      vuln.package.name,
      vuln.package.version,
      vuln.title,
      vuln.severity,
      vuln.cvss.toString(),
      vuln.cve?.join('; ') || '',
      vuln.description.replace(/"/g, '""'),
      vuln.fixedIn || '',
      vuln.references.join('; ')
    ]);

    const csvContent = [
      headers.join(','),
      ...rows.map(row => row.map(cell => `"${cell}"`).join(','))
    ].join('\n');

    return csvContent;
  }
}

// Factory function
export function createDependencyScanner(config: ScannerConfig): DependencyScanner {
  return new DependencyScanner(config);
}
