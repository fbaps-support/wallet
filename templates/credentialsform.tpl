[% INCLUDE "header.tpl" %]
<p>
<form method="POST" accept-charset="utf-8">
<input type="hidden" name="trackstate" value="[% trackstate %]">
<input type="hidden" name="filter" value="1">
Filter by tag: 
<select name="tag" onChange="form.submit()">
<option value="">All</option>
[% FOREACH tag IN alltags ~%]
	<option value="[% tag %]" [% IF settings.tag == tag %]selected[% END %]>[% tag %]</option>
[% END ~%]
</select>
<input type="checkbox" name="onlymine" [% IF settings.onlymine %]checked[% END %] onClick="form.submit()">Only show credentials I own
<input type="submit" value="Go">
</form>
<p>
[% IF (credentials.size == 0) %]
No credentials match your current filtering options.
[%- ELSE -%]
You have access to the following credential[% IF credentials.size !=1 %]s[% END %] in the wallet:
<form method="POST" accept-charset="utf-8">
<input type="hidden" name="trackstate" value="[% trackstate %]">
<table class="realtable">
<tr><th>Description</th><th>Granted by</th><th>Tags</th><th><a href="help.html#flags">Flags</a></th><th>&nbsp;</th></tr>
[% FOREACH credential IN credentials ~%]
	<tr>
	<td
		[%= IF (credential.insecure || credential.expired) ~%]
			class="warning"
		[%~ END ~%]
	>[% credential.description %]</td>
	<td>[% credential.grantedby %]</td>
	<td>
		[%~ IF (credential.tags.size == 0) ~%]
			&nbsp;
		[%~ ELSE ~%]
			[%~ FOREACH tag IN credential.tags ~%]
				<a href="?trackstate=[% trackstate %]&filter=1&tag=[% tag %]">[% tag %]</a>
				[%~ IF !loop.last() %], [% END ~%]
			[%~ END ~%]
		[%~ END ~%]
	</td>
	<td><tt>
		[%~ IF credential.is_owner %]O[% END ~%]
		[%~ IF !credential.aeskey.defined %]M[% END ~%]
		[%~ IF credential.insecure %]I[% END ~%]
		[%~ IF credential.expiry_weeks == 0 %]N[% END ~%]
		[%~ IF credential.expired %]E[% END ~%]
	</tt></td>
	<td>
	<input type="submit" name="view[% credential.ID %]" value="View">
	</td>
	</tr>
[%~ END ~%]
</table>
</form>
[% END %]
[% INCLUDE "footer.tpl" %]
