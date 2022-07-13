[% INCLUDE "header.tpl" %]
[% INCLUDE "userlist.js" %]

<form method="POST" name="form" onSubmit="return validate()" accept-charset="utf-8">
<input type="hidden" name="trackstate" value="[% trackstate %]">
<table class="formtable">
<tr>
    <td>Description:</td>
    <td><input type="text" name="description" id="description" size="40" value="[% details.description %]"></td>
</tr>
<tr>
    <td>Tags:</td>
    <td><input type="text" name="tags" size="40" value="
        [%~ FOREACH tag IN details.tags ~%]
                [%~ tag ~%]
                [%~ IF !loop.last() %], [% END ~%]
        [%~ END ~%]
    ">
    </td>
</tr>
<tr>
    <td>Expiry time (weeks):</td>
    <td>
    <input type="text" name="expiry_weeks" size="40" value="
        [%~ IF details.expiry_weeks > 0 ~%]
                [%~ details.expiry_weeks ~%]
        [%~ END ~%]
    ">
    </td>
</tr>
[% IF details.last_changed.defined ~%]
<tr>
    <td>Last Changed:</td>
    <td 
        [%~ IF ((details.expiry_weeks != 0 && details.weeks > details.expiry_weeks) || details.insecure) ~%]
                class="warning"
        [%~ END ~%]
    >
    [%~ details.last_changed %] ([% details.weeks %] week[% IF details.weeks != 1 %]s[% END %] ago)
    [%~ IF details.insecure ~%]-- Marked INSECURE[%~ END ~%]
    </td>
</tr>
[% END %]
<tr>
    <td>Ownership:</td>
    <td>
    	<div id="ownerselect">JavaScript needed</div>
    </td>
</tr>
<tr>
    <td>Have access:</td>
    <td>
	<div id="userselect">>JavaScript needed</div>
        or <select id="likeselect" onchange="addlike();">
	<option value="">Add all users who also have access to...</option>
[% FOREACH other IN othercreds %]
	<option value="[% loop.index %]">[% other.0 %]</option>
[%~ END %]
        </select>
    </td>
</tr>
<tr>
    <td>Your wallet password:</td>
    <td>
    <input id="password" type="password" name="password" size="40">
    </td>
</tr>
<tr>
    <td>Credentials:</td>
    <td>
    <textarea name="credentials" cols="80" rows="5">
    [%~ details.credentials ~%]
    </textarea>
    </td>
</tr>
<tr>
    <td colspan="2" align="center">
    <input type="submit" name="save" value="Save details">
    </td>
</tr>
</table>
</form>
<script type="text/javascript">

var users = new Array(
[% FOREACH details.userlist %]
	new Array("[% username %]", "[% ID %]", [% user ? "true" : "false" %])[% IF !loop.last %],[% END %]
[% END %]
);

var owners = Array(
[% FOREACH details.userlist %]
	new Array("[% username %]", "[% ID %]", [% owner ? "true" : "false" %])[% IF !loop.last %],[% END %]
[% END %]
);

var othercreds = new Array(
[%~ FOREACH cred IN othercreds %]
	new Array(
		[%~ FOREACH ent IN cred ~%]
		[%~ IF !loop.first %][% ent %][% END ~%]
		[%~ IF !loop.first && !loop.last ~%],[%~ END ~%]
		[%~ END ~%]
	)
	[%~ IF !loop.last ~%],[% END %]
[%~ END %]
);

var ownerupdate, userupdate;
function post_owner_update(i)
{
	if (owners[i][2] && !users[i][2])
	{
		users[i][2] = true;
		userupdate();
	}
}
function post_user_update(i)
{
	if (owners[i][2] && !users[i][2])
	{
		owners[i][2] = false;
		ownerupdate();
	}
}

function addlike()
{
	var likeselect = document.getElementById("likeselect");
	var i = likeselect.value;
	if (i != "" && i < othercreds.length)
	{
		var j;
		for (j=0; j<othercreds[i].length; j++)
		{
			users[othercreds[i][j]][2] = true;
		}
	}
	likeselect.selectedIndex = 0;
	userupdate();
}

function validate()
{
        var password = document.getElementById("password");
        if (password.value == "")
        {
            alert("Please enter your wallet password");
            return false;
        }

	var description = document.getElementById("description");
	if (description.value == "")
	{
		alert("Please enter a description");
		return false;
	}

	var n_owners = 0;
	var n_users = 0;
	for (i=0; i < owners.length; i++)
	{
		if (owners[i][2])
		{
			n_owners++;
		}
	}
	for (i=0; i < users.length; i++)
	{
		if (users[i][2])
		{
			n_users++;
		}
	}
	if (n_owners == 0)
	{
		alert("You cannot remove all owners from a credential");
		return false;
	}
	if (n_users == 0)
	{
		alert("You cannot remove all users from a credential");
		return false;
	}
        return true;
}

ownerupdate = createselect("ownerselect", "owner", "Add owner", owners, post_owner_update);
userupdate = createselect("userselect", "user", "Add user", users, post_user_update);

</script>
[% INCLUDE "footer.tpl" %]
