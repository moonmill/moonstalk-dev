// TODO: must currently be called after kit, to add to namespace; instead give own namespace

moonstalk_Kit.addFormTableItem = function(selector,top) {
	// will clone the li with class 'template' and append it to 'to' before the first li with class 'component'
	var selected = $(selector);
	var $template = selected.find('#template'); //should get the li with class template that we use to clone.
	var $clonedli = $template.clone(true); //deep copy
	$clonedli.removeClass("component");
	$clonedli.addClass("item");
	$clonedli.attr("id",null);
	if (selected.hasClass('array')) {
		// rename all the form elements name attribute
		$clonedli.find("select, input, radio, textarea").each(function() { $(this).attr("name", moonstalk_Kit.__setName($(this).attr("name"), moonstalk_Kit.__getNextId(selector))) });
	} else {}; // TODO: set a temporary name for added hashmap items, or use an input named key
	// finally insert before the first li with class 'component'
	$clonedli.insertBefore($(selector).find('li.component').first());
	$clonedli.fadeIn(200).show(300).find('input, textarea, select')[0].focus();
	//$(selector+' #none').hide(300);
	return $clonedli;
};
moonstalk_Kit.newFileItem = function(event) {
	if (!event) { event = window.event; }
	var file = event.target.files[0]	// we take the first file only.
	if (file != null && file != undefined) {
		var id = '#'+event.target.parentNode.parentNode.id;
		var $fileinput = $(event.target).detach();
		// create a new item for this file, removing its file field and replacing it with the choose file input
		var newItem = addFormTableItem(id);
		//newItem.find('input[type=file]').remove();
		newItem.append($fileinput);
		var name = $fileinput.attr("name");
		$fileinput.attr("name", moonstalk_Kit.__setName(name, moonstalk_Kit.__getNextId(id)-1));
		$fileinput.hide();
		// create a new choose file input
		$(id+' #add').append('<input name="'+name+'" type="file" onchange="moonstalk_Kit.newFileItem(event)"/>'); // TODO: preserve the accept as well also we should probably place it into a span
		// set the preview
		var tImg = newItem.find('img');
		if (tImg!=null) {
			var reader = new FileReader();
			reader.onload = function(e) {
				$(tImg).attr('src', e.target.result);
			};
			reader.readAsDataURL(file);
		}
	}
}

moonstalk_Kit.deleteFormTableItem = function(event) {
	var item = $(event.currentTarget).parent();
	var id = '#' + item.parent().attr('id');
	item.fadeOut(200).hide(300);
	item.remove();
	if ($(id).hasClass('array')) {
		moonstalk_Kit.updateFormArray(event,id);
	}
	if ($("li:not('#template,.component')").length == 0) { 	$(ul).find('#none').show(300);};
};

moonstalk_Kit.updateFormArray = function(event, selector) {
	$(selector).find("li:not('#template,.component')").each(function(pos) {
			var nextid = pos+1;
			$(this).find("select, input, radio, textarea").each(function() { $(this).attr("name", moonstalk_Kit.__setName($(this).attr("name"), nextid)) });
	});
};

moonstalk_Kit.enableFormTable = function(selector){
	$(selector).sortable({ items: "li:not(#template,.component)", update: function(event) { moonstalk_Kit.updateFormArray(event,selector);} });
	if ($(selector).hasClass("remove")) {
		$(selector).find("li").each(function(pos) {
			if ($(selector).hasClass("component")==false) {
				$(this).prepend('<span id="remove" onclick="moonstalk_Kit.deleteFormTableItem(event)" title="'+page._removeTitle+'"></span>');
			};
		});
	}
	$(selector).disableSelection();
};
moonstalk_Kit.__setName = function(name, id) {
	return name.replace(/\.\d+(\.?)/, "."+id+"$1");
}
moonstalk_Kit.__getNextId = function(selector) {
	var $lis = $(selector).find("li:not(#template,.component)"); // get all li excluding ignored class/id
	return $lis.length + 1;
}
