import enthraler.HaxeTemplate;
import enthraler.Environment;
import js.d3.D3;
import js.d3.scale.Scale;
import js.d3.layout.Layout;
import js.Browser.*;
import tink.Json;

typedef CsvData = Array<Array<String>>;

typedef ResponseGroups = Array<{value: String, group: String, radius: Int}>

typedef Question = {
    question: String,
    type: QuestionType
}

enum QuestionType {
    GroupedAnswer;
    GroupedWeightedAnswer(groups: ResponseGroups);
    FreeText;
}

typedef AuthorData = {
    /**
    Column numbers that contain profile info.
    First row should be a header with the column titles.
    **/
    var profileInfo: Array<Int>;
    /**
    The list of questions we are asking.
    See tink_json for how these are displayed in JSON form: https://github.com/haxetink/tink_json#enums
    **/
    var questions: Array<Question>;
    /**
    All the survey responses.
    An Array of CSV rows, containing an Array of CSV column values.
    In this rows should represent each respondant, columns each question, and cells each individual response.
    The first row should be the header with the question title.
    **/
    var responses: CsvData;
}

typedef CircleNode = {
	responseIndex: Int,
	radius: Float,
	color: String,
	x: Float,
	y: Float,
	cx: Float,
	cy: Float,
};

extern class D3Tip {

}

/**
	Haxe JS Enthraler Component.

	We define `Hello` as the class to export in build.hxml.
	Enthraler components need an AMD definition, and if you implement the `HaxeTemplate` class, it will generate an AMD definition for you.

	It will also take care of loading dependencies if you add `@:enthralDependency('amdPath', HaxeExtern)`.
	Note: the macro will overwrite the `@:native` metadata on any externs to a custom global variable, and set that variable during the define function.
**/
@:enthralerDependency('cdnjs/d3/3.5.17/d3.min', D3)
@:enthralerDependency('cdnjs/d3-tip/0.7.1/d3-tip.min', D3Tip)
class AgreeOrDisagree implements HaxeTemplate<AuthorData> {
	// Visualisation config
	var width = 960;
	var height = 500;
	var padding = 6;
	var maxRadius = 12;
	var numberOfNodes(get, null): Int;
	var numberOfClusters: Int;

	function get_numberOfNodes(): Int {
		return this.authorData.responses.length;
	}

	// Enthraler stuff
	var environment: Environment;
	var authorData: AuthorData;

	// D3 stuff
	var circle: Dynamic;
	var nodes: Array<CircleNode>;
	var xScale: Ordinal;
	var force: Force; // See https://github.com/d3/d3-3.x-api-reference/blob/master/Force-Layout.md

	public function new(environment:Environment) {
		// this.header = new JQuery('<h1>').appendTo(environment.container);
		this.environment = environment;
	}

	public function render(plainJsonData: {}) {
		// Enthraler will have done a plain JSON.parse() rather than using tink.Json.parse()
		// We need to re-parse it if we want it to support our enums correctly.
		var jsonStr = haxe.Json.stringify(plainJsonData);
		this.authorData = tink.Json.parse(jsonStr);
		var groups = [];
		for (respondant in authorData.responses) {
			var community = respondant[0];
			if (groups.indexOf(community) == -1) {
				groups.push(community);
			}
      	}
		// environment.container.innerHTML = 'Hello ${groups}, I am rendered using Haxe!';
		this.drawTheDots();
		environment.requestHeightChange();
	}

	function setNumberOfGroups(num: Int) {
		this.numberOfClusters = num;
		this.xScale = D3.scale
			.ordinal()
			.domain(D3.range(num))
			.rangePoints([0, width], 1);
	}

	function setRadiusScaling(showRadius: Bool) {}

	function setGroupColouring(questionNumber: Int) {}

    function drawTheDots() {
		setNumberOfGroups(1);

		var color = D3.scale.category10().domain(D3.range(numberOfClusters));

		this.nodes = D3.range(numberOfNodes).map(function(index) {
			var i = Math.floor(Math.random() * numberOfClusters),
				v = (i + 1) / numberOfClusters * -Math.log(Math.random());
			return {
				responseIndex: index,
				radius: Math.sqrt(v) * maxRadius,
				color: color.call(i),
				cx: xScale.call(i),
				cy: height / 2
			};
		});

		this.force = D3.layout
			.force()
			.nodes(nodes)
			.size([width, height]);

		var svg = D3
			.select("body")
			.append("svg")
			.attr("width", width)
			.attr("height", height);

		this.circle = svg
			.selectAll("circle")
			.data(nodes)
			.enter()
			.append("circle")
			.attr("r", function(d) {
				return d.radius;
			})
			.style("fill", function(d) {
				return d.color;
			})
			// Note, we are casting to dynamic to avoid Haxe binding `force.drag` to `force`.
			// In this case we actually want JS's super weird behaviour of making "this" bind to whatever the hell it's attached to when it's called.
			.call((force:Dynamic).drag);

		force
			.gravity(0)
			.charge(0)
			.on("tick", tick)
			.start();

		var q = 0;
		window.addEventListener('keydown', function () {
			showQuestion(q++);
		});

		// Resize the iframe to fit the new height.
		environment.requestHeightChange();
	}

	function showQuestion(questionIndex: Int) {
		var question = this.authorData.questions[questionIndex];
		trace('Q: ${question.question}');

		var allGroups = [],
			getResponse:String->{group: String, radius: Int};

		function addGroup(name: String) {
			if (allGroups.indexOf(name) == -1) allGroups.push(name);
		}

		switch question.type {
			case GroupedAnswer:
				getResponse = function (response: String) return {group: response, radius: 1};
				for (respondant in authorData.responses) {
					var response = respondant[questionIndex];
					addGroup(response);
				}
			case GroupedWeightedAnswer(groups):
				getResponse = function (response) {
					for (group in groups) {
						if (group.value == response) {
							return group;
						}
					}
					return {group: 'Unanswered', radius: 0};
				}
				for (group in groups) {
					addGroup(group.group);
				}
			case FreeText:
				trace('not handling free text yet');
				return;
		}

		setNumberOfGroups(allGroups.length);
		nodes = nodes.map(function(node) {
			var respondant = this.authorData.responses[node.responseIndex],
				responseText = respondant[questionIndex],
				response = getResponse(responseText),
				groupIndex = allGroups.indexOf(response.group);
			node.cx = xScale.call(groupIndex);
			node.radius = Math.sqrt(response.radius) * maxRadius;
			return node;
		});
		this.force.resume();
	}

	function updateNodes() {
		setNumberOfGroups(Math.ceil(Math.random() * 5));
		trace("update nodes");
		nodes = nodes.map(function(node) {
			var i = Math.floor(Math.random() * numberOfClusters),
				v = (i + 1) / numberOfClusters * -Math.log(Math.random());
			node.radius = Math.sqrt(v) * maxRadius;
			node.cx = xScale.call(i);
			return node;
		});
		this.force.resume();
	}

	// Move nodes toward cluster focus.
	function gravity(alpha: Float) {
		return function(d: CircleNode) {
			d.y += (d.cy - d.y) * alpha;
			d.x += (d.cx - d.x) * alpha;
		};
	}

	function collide(alpha: Float) {
		var quadtree = D3.geom.quadtree(nodes);
		return function(d: CircleNode) {
			var r = d.radius + maxRadius + padding,
				nx1 = d.x - r,
				nx2 = d.x + r,
				ny1 = d.y - r,
				ny2 = d.y + r;
			quadtree.visit(function(quad, x1, y1, x2, y2) {
				var point: CircleNode = quad.point;
				if (point != null && point != d) {
					var x = d.x - point.x,
						y = d.y - point.y,
						l = Math.sqrt(x * x + y * y),
						isSameGroup = (d.cx == point.cx), //(d.color != point.color),
						r =
							d.radius +
							point.radius +
							(isSameGroup ? 1 : padding);
					if (l < r) {
						l = (l - r) / l * alpha;
						d.x -= x *= l;
						d.y -= y *= l;
						point.x += x;
						point.y += y;
					}
				}
				return x1 > nx2 || x2 < nx1 || y1 > ny2 || y2 < ny1;
			});
		};
	}

	function tick(e) {
		if (this.circle == null) {
			throw new js.Error('circle is null');
		}
		this.circle
			.each(gravity(0.2 * e.alpha))
			.each(collide(0.5))
			.attr("cx", function(d) {
				return d.x;
			})
			.attr("cy", function(d) {
				return d.y;
			})
			// Jason: Added "r" and "fill" in the hope of rendering an update.
			.attr("r", function(d) {
				return d.radius;
			})
			.style("fill", function(d) {
				return d.color;
			});
	}
}


typedef AgreeOrDisagreeProps = {
	name:String
};
