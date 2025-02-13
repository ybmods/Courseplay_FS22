--- AI job derived of AIJobFieldWork.
---@class AIJobFieldWorkCp : AIJobFieldWork
AIJobFieldWorkCp = {}
local AIJobFieldWorkCp_mt = Class(AIJobFieldWorkCp, AIJobFieldWork)

---Localization text symbols.
AIJobFieldWorkCp.translations = {
    JobName = "CP_job_fieldWork",
    GenerateButton = "FIELDWORK_BUTTON"
}

function AIJobFieldWorkCp.new(isServer, customMt)
	local self = AIJobFieldWork.new(isServer, customMt or AIJobFieldWorkCp_mt)
	
	self.fieldWorkTask = AITaskFieldWorkCp.new(isServer, self)
	-- Switches the AITaskFieldWork with AITaskFieldWorkCp.
	-- TODO: Consider deriving AIJobFieldWorkCp of AIJob and implement our own logic instead.
	local ix
	for i,task in pairs(self.tasks) do 
		if self.tasks[i]:isa(AITaskFieldWork) then 
			ix = i
			break
		end
	end
	self.fieldWorkTask.taskIndex = ix
	self.tasks[ix] = self.fieldWorkTask
	
	self.lastPositionX, self.lastPositionZ = math.huge, math.huge
	self.hasValidPosition = false

	--- Small translation fix, needs to be removed once giants fixes it.
	local ai = g_currentMission.aiJobTypeManager
	ai:getJobTypeByIndex(ai:getJobTypeIndexByName("FIELDWORK_CP")).title = g_i18n:getText(AIJobFieldWorkCp.translations.JobName)

	self.fieldPositionParameter = AIParameterPosition.new()
	self.fieldPositionParameter.setValue = function (self, x, z)
		self:setPosition(x, z)		
	end
	self.fieldPositionParameter.isCpFieldPositionTarget = true

	self:addNamedParameter("fieldPosition", self.fieldPositionParameter )
	local positionGroup = AIParameterGroup.new(g_i18n:getText("CP_jobParameters_fieldPosition_title"))
	positionGroup:addParameter(self.fieldPositionParameter )
	table.insert(self.groupedParameters, positionGroup)

	self.cpJobParameters = CpJobParameters(self)
	CpSettingsUtil.generateAiJobGuiElementsFromSettingsTable(self.cpJobParameters.settingsBySubTitle,self,self.cpJobParameters)

	self.selectedFieldPlot = FieldPlot(g_currentMission.inGameMenu.ingameMap)
	self.selectedFieldPlot:setVisible(false)

	return self
end

function AIJobFieldWorkCp:applyCurrentState(vehicle, mission, farmId, isDirectStart)
	AIJobFieldWorkCp:superClass().applyCurrentState(self, vehicle, mission, farmId, isDirectStart)
	
	local x, z = nil

	if vehicle.getLastJob ~= nil then
		local lastJob = vehicle:getLastJob()

		if not isDirectStart and lastJob ~= nil and lastJob.cpJobParameters then
			x, z = lastJob.fieldPositionParameter:getPosition()
		end
	end

	if x == nil or z == nil then
		x, _, z = getWorldTranslation(vehicle.rootNode)
	end

	self.fieldPositionParameter:setPosition(x, z)
end

function AIJobFieldWorkCp:setValues()
	AIJobFieldWorkCp:superClass().setValues(self)
end

--- Called when parameters change, scan field
function AIJobFieldWorkCp:validate(farmId)
	local isValid, errorMessage = AIJobFieldWork:superClass().validate(self, farmId)
	if not isValid then
		return isValid, errorMessage
	end

	local vehicle = self.vehicleParameter:getVehicle()

	-- everything else is valid, now find the field
	local tx, tz = self.fieldPositionParameter:getPosition()
	if tx == self.lastPositionX and tz == self.lastPositionZ then
		CpUtil.debugVehicle(CpDebug.DBG_HUD, vehicle, 'Position did not change, do not generate course again')
		return isValid, errorMessage
	else
		self.lastPositionX, self.lastPositionZ = tx, tz
		self.hasValidPosition = true
	end
	self.customField = nil
	local fieldNum = CpFieldUtil.getFieldIdAtWorldPosition(tx, tz)
	CpUtil.infoVehicle(vehicle,'Scanning field %d on %s', fieldNum, g_currentMission.missionInfo.mapTitle)
	self.fieldPolygon = g_fieldScanner:findContour(tx, tz)
	if not self.fieldPolygon then
		local customField = g_customFieldManager:getCustomField(tx, tz)
		if not customField then
			self.hasValidPosition = false
			self.selectedFieldPlot:setVisible(false)
			return false, g_i18n:getText("CP_error_not_on_field")
		else
			CpUtil.infoVehicle(vehicle, 'Custom field found: %s, disabling island bypass', customField:getName())
			self.fieldPolygon = customField:getVertices()
			self.customField = customField
			vehicle:getCourseGeneratorSettings().islandBypassMode:setValue(Island.BYPASS_MODE_NONE)
		end
	end
	if self.fieldPolygon then
		self.selectedFieldPlot:setWaypoints(self.fieldPolygon)
		self.selectedFieldPlot:setVisible(true)
		self.selectedFieldPlot:setBrightColor(true)
	end
	if vehicle then
		if not vehicle:getCanStartCpBaleFinder(self.cpJobParameters) then 
			if not vehicle:hasCpCourse() then 
				return false, g_i18n:getText("CP_error_no_course")
			end
		end
	end
	self.cpJobParameters:validateSettings()
	return true, ''
end

function AIJobFieldWorkCp:drawSelectedField(map)
	if self.selectedFieldPlot then
		self.selectedFieldPlot:draw(map)
	end
end

function AIJobFieldWorkCp:getCpJobParameters()
	return self.cpJobParameters
end

function AIJobFieldWorkCp:getFieldPositionTarget()
	return self.fieldPositionParameter:getPosition()
end

---@return CustomField or nil Custom field when the user selected a field position on a custom field
function AIJobFieldWorkCp:getCustomField()
	return self.customField
end

--- Registers additional jobs.
function AIJobFieldWorkCp.registerJob(self)
	self:registerJobType("FIELDWORK_CP", AIJobFieldWorkCp.translations.JobName, AIJobFieldWorkCp)
end

--- Is course generation allowed ?
function AIJobFieldWorkCp:getCanGenerateFieldWorkCourse()
	return self.hasValidPosition
end

function AIJobFieldWorkCp:getCanStartJob()
	local vehicle = self.vehicleParameter:getVehicle()
	return vehicle and (vehicle:hasCpCourse() or
			self.cpJobParameters.startAt:getValue() == CpJobParameters.START_FINDING_BALES)
end

--- Button callback to generate a field work course.
function AIJobFieldWorkCp:onClickGenerateFieldWorkCourse()
	local vehicle = self.vehicleParameter:getVehicle()
	local settings = vehicle:getCourseGeneratorSettings()
	local status, ok, course = CourseGeneratorInterface.generate(self.fieldPolygon,
			{x = self.lastPositionX, z = self.lastPositionZ},
			settings.isClockwise:getValue(),
			settings.workWidth:getValue(),
			AIUtil.getTurningRadius(vehicle),
			settings.numberOfHeadlands:getValue(),
			settings.startOnHeadland:getValue(),
			settings.headlandCornerType:getValue(),
			settings.headlandOverlapPercent:getValue(),
			settings.centerMode:getValue(),
			settings.rowDirection:getValue(),
			settings.manualRowAngleDeg:getValue(),
			settings.rowsToSkip:getValue(),
			settings.rowsPerLand:getValue(),
			settings.islandBypassMode:getValue(),
			settings.fieldMargin:getValue(),
			settings.multiTools:getValue(),
			self:isPipeOnLeftSide(vehicle)
	)
	CpUtil.debugFormat(CpDebug.DBG_COURSES, 'Course generator returned status %s, ok %s, course %s', status, ok, course)
	if not status then
		g_gui:showInfoDialog({
			dialogType = DialogElement.TYPE_ERROR,
			text = g_i18n:getText('CP_error_could_not_generate_course')
		})
		return false
	end

	vehicle:setFieldWorkCourse(course)
end

function AIJobFieldWorkCp:isPipeOnLeftSide(vehicle)
	if AIUtil.getImplementOrVehicleWithSpecialization(vehicle, Combine) then
		local pipeAttributes = {}
		local combine = ImplementUtil.findCombineObject(vehicle)
		ImplementUtil.setPipeAttributes(pipeAttributes, vehicle, combine)
		return pipeAttributes.pipeOnLeftSide
	else
		return true
	end
end

function AIJobFieldWorkCp:getPricePerMs()
	local modifier = g_Courseplay.globalSettings:getSettings().wageModifier:getValue()/100
	return AIJobFieldWorkCp:superClass().getPricePerMs(self) * modifier
end

--- Automatically repairs the vehicle, depending on the auto repair setting.
--- Currently repairs all AI drivers.
function AIJobFieldWorkCp:onUpdateTickWearable(...)
	if self:getIsAIActive() and self:getUsageCausesDamage() then 
		if self.rootVehicle and self.rootVehicle.getIsCpActive and self.rootVehicle:getIsCpActive() then 
			local dx =  g_Courseplay.globalSettings:getSettings().autoRepair:getValue()
			local repairStatus = (1 - self:getDamageAmount())*100
			if repairStatus < dx then 
				self:repairVehicle()
			end		
		end
	end
end
Wearable.onUpdateTick = Utils.appendedFunction(Wearable.onUpdateTick, AIJobFieldWorkCp.onUpdateTickWearable)

--- for reload, messing with the internals of the job type manager so it uses the reloaded job
if g_currentMission then
	local myJobTypeIndex = g_currentMission.aiJobTypeManager:getJobTypeIndexByName('FIELDWORK_CP')
	if myJobTypeIndex then
		local myJobType = g_currentMission.aiJobTypeManager:getJobTypeByIndex(myJobTypeIndex)
		myJobType.classObject = AIJobFieldWorkCp
	end
end

AIJobTypeManager.loadMapData = Utils.appendedFunction(AIJobTypeManager.loadMapData,AIJobFieldWorkCp.registerJob)

function AIJobFieldWorkCp:getIsAvailableForVehicle(vehicle)
	return vehicle.getCanStartCpFieldWork and vehicle:getCanStartCpFieldWork()
end

function AIJobFieldWorkCp:resetStartPositionAngle(vehicle)
	local x, _, z = getWorldTranslation(vehicle.rootNode) 
	local dirX, _, dirZ = localDirectionToWorld(vehicle.rootNode, 0, 0, 1)

	self.positionAngleParameter:setPosition(x, z)
	local angle = MathUtil.getYRotationFromDirection(dirX, dirZ)
	self.positionAngleParameter:setAngle(angle)

	self.fieldPositionParameter:setPosition(x, z)
end
function AIJobFieldWorkCp:getVehicle()
	return self.vehicleParameter:getVehicle() or self.vehicle
end

function AIJobFieldWorkCp:setVehicle(v)
	self.vehicle = v
end