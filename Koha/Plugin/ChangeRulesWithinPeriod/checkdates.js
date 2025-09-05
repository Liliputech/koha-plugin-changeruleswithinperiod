$(document).ready(function() {
    const smartrulespath = '/cgi-bin/koha/admin/smart-rules.pl';
    if (window.location.pathname.startsWith(smartrulespath)) {
	fetch('/api/v1/contrib/changerules/static/modal.html')
	    .then(response => response.text())
	    .then(html => {$('body').append(html)})
	    .catch(error => {
		console.error('Error fetching the Modal file:', error)});

	fetch('/api/v1/contrib/changerules/config')
	    .then(response => response.json())
	    .then(data => {
		const today = new Date();
		today.setHours(0, 0, 0, 0);

		const startDate = data.start_date ? new Date(data.start_date) : null;
		const endDate = data.end_date ? new Date(data.end_date) : null;

		if (startDate && endDate && today >= startDate && today <= endDate) {
		    $('#changerulesmodal').modal('show');
		}
	    })
	    .catch(error => {
		console.error('Error fetching the plugin settings :', error);
	    });
    }
});
