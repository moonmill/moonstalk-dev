var validate = {}
for (var name in page.data||{}){
	if (typeof(page.data[name])=="object" && page.data[name].validate){
		var tag = $("[name='"+name+"']")
		if (tag.prop('nodeName')=="INPUT"){
			tag.bindWithDelay("keyup",function(){moonstalk_Kit.Validate(this)},500) // TODO: make delay/aggregation configurable, e.g. only for fields with server-side validation
		}
		else if (tag.prop('nodeName')=="SELECT"){
			tag.change(function(){moonstalk_Kit.Validate(this)})
		}
	};
}

moonstalk_Kit.Validate = function(field) {
	var validation = page.data[field.name];
	if (!validation){ return } else if (!validate[validation.validate]) {
		validation.validate = "_Undefined"
		console.log('undefined validation: \''+validation.validate+'\' for field \''+field.name+'\'')
	}
	var value = $(field).val();
	if(value.length==0){value=null};
	var validated = validate[validation.validate](value,validation.arg);
	if (validated == validation.validated_class){return} // skip if unchanged
	field = $(field);
	validation.validated_class = validated;

	if(validation.valid || page._validation_default.valid){field.removeClass(validation.valid || page._validation_default.valid)};
	field.removeClass(validation.error || page._validation_default.error);
	if(validation.default){field.removeClass(validation.default)};

	var message,_class;
	if (!value && (validation.optional || typeof validation.default =='string')){
		_class = validation.default
	} else if (validated ==false){
		_class = validation.error || page._validation_default.error;
		message = validation.message
	} else if (validated ==true){
		if (typeof validation.valid =='string'){
			_class = validation.valid
		}else{
			_class = page._validation_default.valid
		}
	};
	if (_class=="none" || _class==""){_class=null}
	if (_class){console.log("new class: "+_class);field.addClass(_class)}
	moonstalk_Kit.ToggleValidationMessage(field, message)
}

moonstalk_Kit.ToggleValidationMessage = function(field,message){
	var messageTag = field.siblings('strong')[0];
	if (!messageTag){return}
	if (!message){
		messageTag.fadeOut(300).hide();
	} else {
		messageTag.html(message).fadeIn(150);
	};
};
validate._Undefined = function(value) {return true};
validate.Length = function(value,arg) {
	arg = arg || {min:1};
	if(typeof(value) =="number"){value = value.toString()};
	if (arg.number && !validate.Number(value)) {return false}
	else if (!value || arg.min!=null && value.length <arg.min || (arg.max!=null && value.length >arg.max)) {return false}
	else {return true};
};
validate.Number = function(value,arg) {
	if (value=="" || value==null){return false}
	arg = arg || {min:0};
	value = Number(value);
	if (!value || arg.max!=null && value >arg.max || arg.min!=null && value <arg.min) {return false}
	else {return true};
};
validate.Digits = function(value,arg) {
	if (value=="" || value==null){return false}
	arg = arg || {min:1}
	arg.number = true
	return validate.Length(value.replace( /\D+/g, ''),arg)
};
validate.Email = function(value) {
	if ((value||"").match(/.+@[a-z0-9][a-z0-9\-]+\.[a-z]{2,}/i)){return true}else{return false};
};
validate.Date = function(value,arg) {
	// TODO: min/max
	if (!value){return false}
	if (!value.indexOf("-")&&!value.indexOf("/")){return false}
	value = value.replace( /^\D+/g, '')
	if (!value || value.length <6){return false}
	return true
};
