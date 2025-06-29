import { EventEmitter } from 'events';
import crypto from 'crypto';
import { logger } from '../utils/logger';

export interface DataSubject {
  id: string;
  email: string;
  firstName?: string;
  lastName?: string;
  dateOfBirth?: Date;
  nationality?: string;
  consentRecords: ConsentRecord[];
  dataProcessingActivities: DataProcessingActivity[];
  createdAt: Date;
  updatedAt: Date;
}

export interface ConsentRecord {
  id: string;
  dataSubjectId: string;
  purpose: string;
  lawfulBasis: LawfulBasis;
  consentGiven: boolean;
  consentWithdrawn: boolean;
  consentDate: Date;
  withdrawalDate?: Date;
  consentMethod: ConsentMethod;
  consentVersion: string;
  processingCategories: string[];
  dataCategories: string[];
  retentionPeriod: number; // in days
  thirdPartySharing: boolean;
  thirdParties?: string[];
  metadata: Record<string, any>;
}

export interface DataProcessingActivity {
  id: string;
  dataSubjectId: string;
  activityType: string;
  purpose: string;
  lawfulBasis: LawfulBasis;
  dataCategories: string[];
  processingMethods: string[];
  retentionPeriod: number;
  thirdPartyInvolvement: boolean;
  crossBorderTransfer: boolean;
  safeguards?: string[];
  timestamp: Date;
  metadata: Record<string, any>;
}

export interface DataSubjectRequest {
  id: string;
  dataSubjectId: string;
  requestType: DataSubjectRightType;
  status: RequestStatus;
  requestDate: Date;
  completionDate?: Date;
  requestDetails: Record<string, any>;
  responseData?: any;
  verificationMethod: string;
  processingNotes: string[];
}

export interface PrivacyImpactAssessment {
  id: string;
  projectName: string;
  description: string;
  dataController: string;
  dataProcessor?: string;
  dataCategories: string[];
  processingPurposes: string[];
  lawfulBasis: LawfulBasis[];
  riskLevel: RiskLevel;
  riskFactors: string[];
  mitigationMeasures: string[];
  dpoConsultation: boolean;
  supervisoryAuthorityConsultation: boolean;
  status: PIAStatus;
  createdBy: string;
  reviewedBy?: string;
  approvedBy?: string;
  createdAt: Date;
  reviewedAt?: Date;
  approvedAt?: Date;
}

export enum LawfulBasis {
  CONSENT = 'consent',
  CONTRACT = 'contract',
  LEGAL_OBLIGATION = 'legal_obligation',
  VITAL_INTERESTS = 'vital_interests',
  PUBLIC_TASK = 'public_task',
  LEGITIMATE_INTERESTS = 'legitimate_interests'
}

export enum ConsentMethod {
  EXPLICIT = 'explicit',
  IMPLIED = 'implied',
  OPT_IN = 'opt_in',
  OPT_OUT = 'opt_out'
}

export enum DataSubjectRightType {
  ACCESS = 'access',
  RECTIFICATION = 'rectification',
  ERASURE = 'erasure',
  RESTRICT_PROCESSING = 'restrict_processing',
  DATA_PORTABILITY = 'data_portability',
  OBJECT = 'object',
  WITHDRAW_CONSENT = 'withdraw_consent'
}

export enum RequestStatus {
  PENDING = 'pending',
  IN_PROGRESS = 'in_progress',
  COMPLETED = 'completed',
  REJECTED = 'rejected',
  PARTIALLY_FULFILLED = 'partially_fulfilled'
}

export enum RiskLevel {
  LOW = 'low',
  MEDIUM = 'medium',
  HIGH = 'high',
  VERY_HIGH = 'very_high'
}

export enum PIAStatus {
  DRAFT = 'draft',
  UNDER_REVIEW = 'under_review',
  APPROVED = 'approved',
  REJECTED = 'rejected',
  REQUIRES_REVISION = 'requires_revision'
}

export class GDPRService extends EventEmitter {
  private readonly RESPONSE_DEADLINE_DAYS = 30;
  private readonly BREACH_NOTIFICATION_HOURS = 72;

  constructor(
    private readonly dataSubjectRepository: any,
    private readonly consentRepository: any,
    private readonly auditService: any,
    private readonly anonymizationService: any,
    private readonly notificationService: any
  ) {
    super();
  }

  // Consent Management
  async recordConsent(consentData: Partial<ConsentRecord>): Promise<ConsentRecord> {
    try {
      const consent: ConsentRecord = {
        id: crypto.randomUUID(),
        dataSubjectId: consentData.dataSubjectId!,
        purpose: consentData.purpose!,
        lawfulBasis: consentData.lawfulBasis!,
        consentGiven: consentData.consentGiven!,
        consentWithdrawn: false,
        consentDate: new Date(),
        consentMethod: consentData.consentMethod!,
        consentVersion: consentData.consentVersion || '1.0',
        processingCategories: consentData.processingCategories || [],
        dataCategories: consentData.dataCategories || [],
        retentionPeriod: consentData.retentionPeriod || 365,
        thirdPartySharing: consentData.thirdPartySharing || false,
        thirdParties: consentData.thirdParties,
        metadata: consentData.metadata || {}
      };

      await this.consentRepository.create(consent);

      // Log consent event
      await this.auditService.logEvent({
        eventType: 'CONSENT_RECORDED',
        dataSubjectId: consent.dataSubjectId,
        details: {
          consentId: consent.id,
          purpose: consent.purpose,
          lawfulBasis: consent.lawfulBasis,
          consentMethod: consent.consentMethod
        },
        timestamp: new Date()
      });

      this.emit('consentRecorded', consent);
      logger.info(`Consent recorded for data subject: ${consent.dataSubjectId}`);

      return consent;

    } catch (error) {
      logger.error('Failed to record consent:', error);
      throw new Error(`Consent recording failed: ${error}`);
    }
  }

  async withdrawConsent(dataSubjectId: string, consentId: string, reason?: string): Promise<void> {
    try {
      const consent = await this.consentRepository.findById(consentId);
      if (!consent || consent.dataSubjectId !== dataSubjectId) {
        throw new Error('Consent record not found');
      }

      if (consent.consentWithdrawn) {
        throw new Error('Consent already withdrawn');
      }

      await this.consentRepository.update(consentId, {
        consentWithdrawn: true,
        withdrawalDate: new Date(),
        metadata: {
          ...consent.metadata,
          withdrawalReason: reason
        }
      });

      // Trigger data processing restriction
      await this.restrictProcessing(dataSubjectId, consent.purpose);

      // Log withdrawal event
      await this.auditService.logEvent({
        eventType: 'CONSENT_WITHDRAWN',
        dataSubjectId,
        details: {
          consentId,
          purpose: consent.purpose,
          reason
        },
        timestamp: new Date()
      });

      this.emit('consentWithdrawn', { dataSubjectId, consentId, reason });
      logger.info(`Consent withdrawn for data subject: ${dataSubjectId}`);

    } catch (error) {
      logger.error('Failed to withdraw consent:', error);
      throw new Error(`Consent withdrawal failed: ${error}`);
    }
  }

  // Data Subject Rights
  async handleDataSubjectRequest(requestData: Partial<DataSubjectRequest>): Promise<DataSubjectRequest> {
    try {
      const request: DataSubjectRequest = {
        id: crypto.randomUUID(),
        dataSubjectId: requestData.dataSubjectId!,
        requestType: requestData.requestType!,
        status: RequestStatus.PENDING,
        requestDate: new Date(),
        requestDetails: requestData.requestDetails || {},
        verificationMethod: requestData.verificationMethod || 'email',
        processingNotes: []
      };

      // Verify data subject identity
      await this.verifyDataSubjectIdentity(request.dataSubjectId, request.verificationMethod);

      // Process request based on type
      switch (request.requestType) {
        case DataSubjectRightType.ACCESS:
          await this.processAccessRequest(request);
          break;
        case DataSubjectRightType.RECTIFICATION:
          await this.processRectificationRequest(request);
          break;
        case DataSubjectRightType.ERASURE:
          await this.processErasureRequest(request);
          break;
        case DataSubjectRightType.RESTRICT_PROCESSING:
          await this.processRestrictionRequest(request);
          break;
        case DataSubjectRightType.DATA_PORTABILITY:
          await this.processPortabilityRequest(request);
          break;
        case DataSubjectRightType.OBJECT:
          await this.processObjectionRequest(request);
          break;
        case DataSubjectRightType.WITHDRAW_CONSENT:
          await this.processConsentWithdrawalRequest(request);
          break;
      }

      // Log request
      await this.auditService.logEvent({
        eventType: 'DATA_SUBJECT_REQUEST',
        dataSubjectId: request.dataSubjectId,
        details: {
          requestId: request.id,
          requestType: request.requestType,
          status: request.status
        },
        timestamp: new Date()
      });

      this.emit('dataSubjectRequest', request);
      return request;

    } catch (error) {
      logger.error('Failed to handle data subject request:', error);
      throw new Error(`Data subject request failed: ${error}`);
    }
  }

  private async processAccessRequest(request: DataSubjectRequest): Promise<void> {
    try {
      // Collect all personal data for the data subject
      const personalData = await this.collectPersonalData(request.dataSubjectId);
      
      // Include processing activities
      const processingActivities = await this.getProcessingActivities(request.dataSubjectId);
      
      // Include consent records
      const consentRecords = await this.getConsentRecords(request.dataSubjectId);

      const responseData = {
        personalData,
        processingActivities,
        consentRecords,
        dataRetentionPeriods: await this.getRetentionPeriods(request.dataSubjectId),
        thirdPartySharing: await this.getThirdPartySharing(request.dataSubjectId),
        dataTransfers: await this.getCrossBorderTransfers(request.dataSubjectId)
      };

      request.responseData = responseData;
      request.status = RequestStatus.COMPLETED;
      request.completionDate = new Date();

      // Send response to data subject
      await this.notificationService.sendDataAccessResponse(request.dataSubjectId, responseData);

    } catch (error) {
      request.status = RequestStatus.REJECTED;
      request.processingNotes.push(`Access request failed: ${error.message}`);
      throw error;
    }
  }

  private async processErasureRequest(request: DataSubjectRequest): Promise<void> {
    try {
      // Check if erasure is legally required or permitted
      const erasureAssessment = await this.assessErasureRequest(request.dataSubjectId);
      
      if (!erasureAssessment.canErase) {
        request.status = RequestStatus.REJECTED;
        request.processingNotes.push(`Erasure not permitted: ${erasureAssessment.reason}`);
        return;
      }

      // Perform data erasure
      const erasureResult = await this.erasePersonalData(request.dataSubjectId, erasureAssessment.scope);
      
      request.responseData = erasureResult;
      request.status = erasureResult.fullyErased ? RequestStatus.COMPLETED : RequestStatus.PARTIALLY_FULFILLED;
      request.completionDate = new Date();

      // Notify third parties if necessary
      if (erasureAssessment.notifyThirdParties) {
        await this.notifyThirdPartiesOfErasure(request.dataSubjectId, erasureResult);
      }

    } catch (error) {
      request.status = RequestStatus.REJECTED;
      request.processingNotes.push(`Erasure request failed: ${error.message}`);
      throw error;
    }
  }

  // Privacy Impact Assessment
  async createPrivacyImpactAssessment(piaData: Partial<PrivacyImpactAssessment>): Promise<PrivacyImpactAssessment> {
    try {
      const pia: PrivacyImpactAssessment = {
        id: crypto.randomUUID(),
        projectName: piaData.projectName!,
        description: piaData.description!,
        dataController: piaData.dataController!,
        dataProcessor: piaData.dataProcessor,
        dataCategories: piaData.dataCategories || [],
        processingPurposes: piaData.processingPurposes || [],
        lawfulBasis: piaData.lawfulBasis || [],
        riskLevel: piaData.riskLevel || RiskLevel.MEDIUM,
        riskFactors: piaData.riskFactors || [],
        mitigationMeasures: piaData.mitigationMeasures || [],
        dpoConsultation: piaData.dpoConsultation || false,
        supervisoryAuthorityConsultation: piaData.supervisoryAuthorityConsultation || false,
        status: PIAStatus.DRAFT,
        createdBy: piaData.createdBy!,
        createdAt: new Date()
      };

      // Assess risk level automatically
      pia.riskLevel = await this.assessPrivacyRisk(pia);

      // Determine if DPO consultation is required
      if (this.requiresDPOConsultation(pia)) {
        pia.dpoConsultation = true;
      }

      // Determine if supervisory authority consultation is required
      if (this.requiresSupervisoryAuthorityConsultation(pia)) {
        pia.supervisoryAuthorityConsultation = true;
      }

      // Save PIA
      await this.savePrivacyImpactAssessment(pia);

      // Log PIA creation
      await this.auditService.logEvent({
        eventType: 'PIA_CREATED',
        details: {
          piaId: pia.id,
          projectName: pia.projectName,
          riskLevel: pia.riskLevel,
          createdBy: pia.createdBy
        },
        timestamp: new Date()
      });

      this.emit('piaCreated', pia);
      return pia;

    } catch (error) {
      logger.error('Failed to create PIA:', error);
      throw new Error(`PIA creation failed: ${error}`);
    }
  }

  // Data Breach Management
  async reportDataBreach(breachData: {
    description: string;
    dataCategories: string[];
    affectedDataSubjects: number;
    riskLevel: RiskLevel;
    containmentMeasures: string[];
    discoveredAt: Date;
    reportedBy: string;
  }): Promise<void> {
    try {
      const breach = {
        id: crypto.randomUUID(),
        ...breachData,
        reportedAt: new Date(),
        status: 'reported',
        supervisoryAuthorityNotified: false,
        dataSubjectsNotified: false
      };

      // Assess if breach requires notification to supervisory authority
      const requiresNotification = this.assessBreachNotificationRequirement(breach);

      if (requiresNotification) {
        // Check if within 72-hour deadline
        const hoursElapsed = (Date.now() - breach.discoveredAt.getTime()) / (1000 * 60 * 60);
        
        if (hoursElapsed > this.BREACH_NOTIFICATION_HOURS) {
          breach.status = 'late_notification';
          logger.warn(`Data breach notification is late: ${hoursElapsed} hours elapsed`);
        }

        // Notify supervisory authority
        await this.notifySupervisoryAuthority(breach);
        breach.supervisoryAuthorityNotified = true;
      }

      // Assess if data subjects need to be notified
      if (this.requiresDataSubjectNotification(breach)) {
        await this.notifyAffectedDataSubjects(breach);
        breach.dataSubjectsNotified = true;
      }

      // Log breach
      await this.auditService.logEvent({
        eventType: 'DATA_BREACH_REPORTED',
        details: breach,
        timestamp: new Date()
      });

      this.emit('dataBreachReported', breach);

    } catch (error) {
      logger.error('Failed to report data breach:', error);
      throw new Error(`Data breach reporting failed: ${error}`);
    }
  }

  // Utility methods
  private async verifyDataSubjectIdentity(dataSubjectId: string, method: string): Promise<boolean> {
    // Implement identity verification logic
    return true;
  }

  private async collectPersonalData(dataSubjectId: string): Promise<any> {
    // Collect all personal data across systems
    return {};
  }

  private async getProcessingActivities(dataSubjectId: string): Promise<DataProcessingActivity[]> {
    // Get processing activities for data subject
    return [];
  }

  private async getConsentRecords(dataSubjectId: string): Promise<ConsentRecord[]> {
    // Get consent records for data subject
    return [];
  }

  private async restrictProcessing(dataSubjectId: string, purpose: string): Promise<void> {
    // Implement processing restriction logic
  }

  private async erasePersonalData(dataSubjectId: string, scope: any): Promise<any> {
    // Implement data erasure logic
    return { fullyErased: true, erasedSystems: [], retainedSystems: [] };
  }

  private async assessErasureRequest(dataSubjectId: string): Promise<any> {
    // Assess if erasure is legally required/permitted
    return { canErase: true, reason: '', scope: 'all', notifyThirdParties: false };
  }

  private async assessPrivacyRisk(pia: PrivacyImpactAssessment): Promise<RiskLevel> {
    // Implement privacy risk assessment logic
    return RiskLevel.MEDIUM;
  }

  private requiresDPOConsultation(pia: PrivacyImpactAssessment): boolean {
    // Determine if DPO consultation is required
    return pia.riskLevel === RiskLevel.HIGH || pia.riskLevel === RiskLevel.VERY_HIGH;
  }

  private requiresSupervisoryAuthorityConsultation(pia: PrivacyImpactAssessment): boolean {
    // Determine if supervisory authority consultation is required
    return pia.riskLevel === RiskLevel.VERY_HIGH;
  }

  private assessBreachNotificationRequirement(breach: any): boolean {
    // Assess if breach requires notification to supervisory authority
    return breach.riskLevel !== RiskLevel.LOW;
  }

  private requiresDataSubjectNotification(breach: any): boolean {
    // Assess if data subjects need to be notified
    return breach.riskLevel === RiskLevel.HIGH || breach.riskLevel === RiskLevel.VERY_HIGH;
  }

  private async savePrivacyImpactAssessment(pia: PrivacyImpactAssessment): Promise<void> {
    // Save PIA to database
  }

  private async notifySupervisoryAuthority(breach: any): Promise<void> {
    // Notify supervisory authority of breach
  }

  private async notifyAffectedDataSubjects(breach: any): Promise<void> {
    // Notify affected data subjects
  }

  private async notifyThirdPartiesOfErasure(dataSubjectId: string, erasureResult: any): Promise<void> {
    // Notify third parties of data erasure
  }

  private async getRetentionPeriods(dataSubjectId: string): Promise<any> {
    // Get data retention periods
    return {};
  }

  private async getThirdPartySharing(dataSubjectId: string): Promise<any> {
    // Get third party sharing information
    return {};
  }

  private async getCrossBorderTransfers(dataSubjectId: string): Promise<any> {
    // Get cross-border transfer information
    return {};
  }
}
