$(function () {
  const apiVersions = {
    "API9": "version 9",
    "API8": "version 8",
    "API7": "version 7",
    "API6": "version 6",
    "API5": "version 5",
    "API4": "version 4",
  };

  const apiVersion = $('meta[name="version"]').attr('content');

  const readyForDropdownApi = setInterval(function() {
    const $menu = $('#dropdownApiVersionMenu');
    if ($menu.length) {
      clearInterval(readyForDropdownApi);
      createDropdownMenuItems($menu);
      registerDropdownEvents($menu);
    }
  }, 10);

  function createDropdownMenuItems($menu) {
    Object.keys(apiVersions).sort().reverse().forEach(function(version) {
      const $item = $('<a class="dropdown-item" data-value="' + version + '">' + apiVersions[version] + '</a>');

      if (apiVersion === version) {
        $item.addClass('active');
      }

      $menu.append($item);
    });
    $('#dropdownApiVersionButton').html(apiVersions[apiVersion]);
  }

  function registerDropdownEvents($menu) {
    $menu.find('a').each(function () {
      $(this).on('click', function (e) {
        const $target = $(e.target);

        $('#dropdownApiVersionButton').html(apiVersions[$target.data('value')]);
        window.location.href = '../../' + $target.data('value') + '/api/';
      });
    });
  }

  var readyForAffix = setInterval(function() {
    var items = $('#affix ul .bs-docs-sidenav a');
    if (items.length > 0) {
      clearInterval(readyForAffix);
      var obsoleteIds = $.map($('div .obsolete'), function(item) {
        return '#' + $(item).data('id');
      });
      $.each(items, function(idx, item) {
        if (obsoleteIds.indexOf(item.hash) >= 0) {
          $(item).css("text-decoration", 'line-through')
        }
      });
    }
  }, 10);

});
