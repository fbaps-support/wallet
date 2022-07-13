<script type="text/javascript">
// Created a dropdown list with tickboxes. 
// 
// div_id is the ID of a div that should be filled out with this list.
// checkname is the basename of the checkboxes (they'll get names of the form checkname+userid)
// prompt is the name of the first select element.
// user_list is an array of arrays of the form (username, userid, selected (true/false))
// post_change_function, if not null, is a function which will be called after each change
//
function createselect(div_id, checkname, prompt, user_list, post_change_function)
{
        var div = document.getElementById(div_id);
	if (typeof(div) == "undefined")
	{
		alert("div " + div_id + " not found");
		return;
	}
	div.innerHTML = "";

	var t = document.createElement("table");
	var tb = document.createElement("tbody");
	t.appendChild(tb);
	var tr = document.createElement("tr");
	tb.appendChild(tr);
	var td = document.createElement("td");
	tr.appendChild(td);
	var s = document.createElement("select");
	td.appendChild(s);
	div.appendChild(t);

	var populate = function() {
		s.length = 0;
		while (tr.cells.length > 1)
		{
			tr.deleteCell(1);
		}
		s.options[0] = new Option(prompt, null);
		for (var i=0; i<user_list.length; i++)
		{
			if (user_list[i][2])
			{
				var td = document.createElement("td");
				tr.appendChild(td);

				var lable = document.createElement("label");
				lable.innerHTML = user_list[i][0];
				td.appendChild(lable);

				var cb = document.createElement("input");
				cb.type = "checkbox";
				cb.value = i;
				cb.name = checkname + user_list[i][1];
				cb.onclick = function() {
					var i = this.value;
					user_list[i][2] = false;
					populate();
					if (post_change_function != null)
					{
						post_change_function(i);
					}
				};
				td.appendChild(cb);
				cb.checked = true;
			}
			else
			{
				s.options[s.length] = 
					new Option(user_list[i][0], i);
			}
		}
	};
	s.onchange = function() { 
		var i = this.value;
		user_list[i][2] = true;
		populate();
		if (post_change_function != null)
		{
			post_change_function(i);
		}
	}
	populate();
	return populate;
}
</script>
