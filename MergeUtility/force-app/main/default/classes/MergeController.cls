public class MergeController 
{
    private static Set<String> sObjectFields = new Set<String>();
    
    @AuraEnabled(cacheable=true)
    public static String readCSVFile(Id contentDocumentId) {
        Map<String, List<Id>> masterIdMap = new Map<String, List<Id>>();
        SobjectWrapperData responseData = new SobjectWrapperData();
        Set<String> accIdSet = new Set<String>();
        List<DataTableColumns> dataColumnsList = new List<DataTableColumns>();
        //CsvWrapperData csvData;
        if (contentDocumentId != null)
        {
            //csvData = new CsvWrapperData();
            ContentVersion contentVersionObj = [ SELECT Id, VersionData FROM ContentVersion WHERE ContentDocumentId =:contentDocumentId ];
            List <String> records = contentVersionObj.VersionData.toString().split( '\n' );
            //Removing the Header
            records.remove( 0 );
            try{
                for(String record : records)
                {
                    if ( record != null ) 
                    {
                        List<String> row = record.split( ',' );
                        String masterId = row[1].replace('\r', '').trim();
                        String victimId = row[0].trim();
                        if(masterId != victimId)
                        {
                            if(!masterIdMap.containsKey(masterId))
                            {
                                accIdSet.add(masterId);
                                masterIdMap.put(masterId, new List<Id>());
                            }
                            masterIdMap.get(masterId).add(victimId);
                            accIdSet.add(victimId);
                        }
                    }
                }
                //csvData.recordDataMap = fetchRecords(accIdSet);
                //csvData.csvRecordsMap = masterIdMap;
                responseData.lstDataTableColumns = fetchColumnList('Account');
                responseData = getMasterDataMap(masterIdMap, fetchRecords(accIdSet), responseData);
                
            }catch(Exception ex)
            {
                system.debug('---ex----'+ex.getStackTraceString());
                system.debug('---ex----'+ex.getMessage());
            }
        }
        return JSON.serialize(responseData);
    }
    
    
    private static SobjectWrapperData getMasterDataMap(Map<String, List<Id>> masterIdMap, Map<String, Account> recordDataMap, SobjectWrapperData wrpData)
    {
        List<Account> masterDataList = new List<Account>();
        Map<Id, List<Account>> victimRecordMap = new Map<Id, List<Account>>();
        Map<Id, Account> victimMasterRecordMap = new Map<Id, Account>();
        for(String masterId : masterIdMap.keySet())
        {
            masterDataList.add(recordDataMap.get(masterId));
            victimRecordMap.put(masterId, new List<Account>());
            for(Id victimId : masterIdMap.get(masterId))
            {
                if(recordDataMap.containskey(victimId))
                {
                    victimRecordMap.get(masterId).add(recordDataMap.get(victimId));
                    victimMasterRecordMap.put(victimId, recordDataMap.get(masterId));
                }
            }
        }
        wrpData.surviorDataList = masterDataList;
        wrpData.victimRecordMap = victimRecordMap;
        wrpData.victimMasterRecordMap = victimMasterRecordMap;
        wrpData.recordDataMap = recordDataMap;
        return wrpData;
    }
    
    
    private static Map<String, Account> fetchRecords(Set<String> accIdSet)
    {
        String sObjectQuery = 'Select Id,Name, '+String.join((Iterable<String>)sObjectFields, ', ') +' from Account where Id in: accIdSet' ;
        return new Map<String, Account>((Account[]) Database.query(sObjectQuery));
        
    }
    
    private static List<DataTableColumns> fetchColumnList(String sobjectName)
    {
        List<DataTableColumns> lstDataColumns = new List<DataTableColumns>();
        lstDataColumns.add(new DataTableColumns('Name', 'Name','text'));
        for(Merge_Concern__c mergeConcernData : [SELECT Id, Field_API_Name__c, Field_Name__c, Is_Force_Overwrite__c
                                                 FROM Merge_Concern__c
                                                 WHERE Object_Name__c = :sobjectName])
        {
            system.debug('--mergeConcernData.Field_API_Name__c---'+sObjectFields.size());
            sObjectFields.add(mergeConcernData.Field_API_Name__c);
            lstDataColumns.add(new DataTableColumns(mergeConcernData.Field_Name__c.trim(), mergeConcernData.Field_API_Name__c.trim(), 'text'));
        }
        
        return lstDataColumns;
    }
    
    @AuraEnabled
    public static void handleMergeRecord(String mergeRecords) 
    {
        SobjectWrapperData mergerRecords = (SobjectWrapperData)JSON.deserialize(mergeRecords, SobjectWrapperData.class);
       // Database.executeBatch(new MergerBatch(mergerRecords.recordDataMap, mergerRecords.victimRecordMap, mergerRecords.victimRecordMap), 1);
       Database.executeBatch(new MergerBatch(mergerRecords), 1);
    }
    
    @AuraEnabled(cacheable=true)
    public static String getSobjectFields(String sobjectName)
    {
        SobjectWrapperData responseData = new SobjectWrapperData();
        Map<String, List<SobjectFields>> sObjectFieldsListMap = new Map<String, List<SobjectFields>>();
        String sObjectApiName ='';
        if(sobjectName.contains('__c'))
        {
            Map<String,String> objNameMap = getObjectName();
            sObjectApiName = objNameMap.get(sObjectApiName);
        } else
        {
            sObjectApiName = sobjectName;
        }
        SObjectType sObjectType = Schema.getGlobalDescribe().get(sObjectApiName);
        Map<String,Schema.SObjectField> mfields = sObjectType.getDescribe().fields.getMap();
        List<SobjectFields> sObjectDetailsList = new List<SobjectFields>();
        for(Schema.SobjectField field : mfields.values()){
            Schema.DescribeFieldResult dfr = field.getDescribe();
            if(dfr.isUpdateable())
            {
                if(!sObjectFieldsListMap.containsKey(sobjectName))
                {
                    sObjectFieldsListMap.put(sobjectName, new List<SobjectFields>());
                }
                sObjectFieldsListMap.get(sobjectName).add(new SobjectFields (dfr.getLabel(), String.valueOf(dfr.getName())));
            }
        }
        
        responseData.sObjectFieldsListMap = sObjectFieldsListMap;
        return JSON.serialize(responseData) ;
    }
    
    private static Map<String,String> getObjectName()
    {
        List<Schema.SObjectType> gd = Schema.getGlobalDescribe().Values();    
        Map<String,String> objName = new Map<String,String>();
        for(Schema.SObjectType f : gd)
        {
            if(f.getDescribe().isCustom())
                objName.put(f.getDescribe().getLabel(),f.getDescribe().getName());
        }
        return objName;
    }
    
    @AuraEnabled
    public static void handleMergeConRecord(String mergeConcernRecord) 
    {
        
        MergeConcernWrp mergeConcernWrpObj = (MergeConcernWrp)JSON.deserialize(mergeConcernRecord, MergeConcernWrp.class);
        system.debug('--mergeConcernData----'+mergeConcernWrpObj.fieldApiList);
        Map<String, Merge_Concern__c> mergeConcernMap = new Map<string, Merge_Concern__c>();
        List<Merge_Concern__c> mergeConcernList = new List<Merge_Concern__c>(); 
        try{
            String sObjectName =mergeConcernWrpObj.objectName;
            List<String> fieldApiNameList = mergeConcernWrpObj.fieldApiList;
            
            List<Merge_Concern__c> mergeConObjList = [SELECT Field_API_Name__c, Is_Force_Overwrite__c FROM Merge_Concern__c  
                                                       where Object_Name__c =: sObjectName AND 
                                                       Field_API_Name__c IN : fieldApiNameList LIMIT 1];
            
            if(!mergeConObjList.isEmpty())
            {
                
                for(Merge_Concern__c mergeConObj :  mergeConObjList)
                {
                    mergeConcernMap.put(mergeConObj.Field_API_Name__c, mergeConObj);
                }
            }
            
            for(String fieldApiName : fieldApiNameList)
            {
                Merge_Concern__c mergeConObj = new Merge_Concern__c();
                if(mergeConcernMap.containsKey(fieldApiName))
                {
                    mergeConObj = mergeConcernMap.get(fieldApiName);
                    mergeConObj.Is_Force_Overwrite__c = mergeConcernWrpObj.isForceOverwrite;
                    mergeConcernList.add(mergeConObj);
                    
                } else
                {
                    mergeConObj = new  Merge_Concern__c(Name = sObjectName+': '+fieldApiName,
														Is_Force_Overwrite__c = mergeConcernWrpObj.isForceOverwrite,
                                                        Field_API_Name__c = fieldApiName,
                                                        Object_Name__c = sObjectName,
                                                        Field_Name__c =getFieldLabelName(sObjectName, fieldApiName));
                    mergeConcernList.add(mergeConObj);
                }
            }
            
            if(!mergeConcernList.isEmpty())
                Database.upsert(mergeConcernList);
            
        }catch (Exception e) {
            system.debug('---e----'+e.getStackTraceString());
            throw new AuraHandledException(e.getMessage());
        }
        
    }
	
    private static String getFieldLabelName( String sobjectName, String fieldApiName)
    {
        List<Schema.DescribeSObjectResult> describeSobjectsResult = Schema.describeSObjects(new List<String>{sobjectName}); 
        System.debug(describeSobjectsResult);
        String objectLabel = describeSobjectsResult[0].getLabel();
        Map<String, Schema.SObjectField> allFields = describeSobjectsResult[0].fields.getMap();
        System.debug(allFields);
        return allFields.get(fieldApiName).getDescribe().getLabel();
    }
    
    public class MergeConcernWrp
    {
        public String objectName;
        public List<String> fieldApiList;
        public Boolean isForceOverwrite;
    }
    public class SobjectFields
    {
        public String label;
        public String value;
        public SobjectFields(String fieldLabel, String fieldApiName)
        {
            this.label = fieldLabel;
            this.value = fieldApiName;  
        }
    }
    
    public class SobjectWrapperData
    {
        public List<Account> surviorDataList;
        public Map<String, Account> recordDataMap;
        public Map<Id, List<Account>> victimRecordMap;
        public Map<Id, Account> victimMasterRecordMap;
        public List<DataTableColumns> lstDataTableColumns;
        public Map<String, List<SobjectFields>> sObjectFieldsListMap;
    }
    
    public class SurvivorData
    {
        public Account acc;
        public String recordLink;
    }
    
    public class DataTableColumns {
        public String label;
        public String fieldName;
        public String type;
        public DataTableColumns(String label, String fieldName, String type)
        {
            this.label     = label;
            this.fieldName = fieldName;
            this.type      = type;          
        }
        
    }
}