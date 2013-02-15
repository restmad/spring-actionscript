/*
 * Copyright 2007-2011 the original author or authors.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
package org.springextensions.actionscript.ioc.factory.config {
	import flash.utils.Dictionary;

	import org.as3commons.eventbus.IEventBus;
	import org.as3commons.lang.ClassUtils;
	import org.as3commons.lang.StringUtils;
	import org.as3commons.logging.api.ILogger;
	import org.as3commons.logging.api.getLogger;
	import org.as3commons.reflect.IMetadataContainer;
	import org.as3commons.reflect.Metadata;
	import org.as3commons.reflect.MetadataArgument;
	import org.as3commons.reflect.Method;
	import org.as3commons.reflect.MethodInvoker;
	import org.springextensions.actionscript.ioc.IDisposable;

	/**
	 * <code>IMetadataProcessor</code> implementation that adds <code>EventBus</code> event handlers based on the annotations found in the object's class.
	 * These annotations mark a public method as an event handler of an event dispatched on the <code>EventBus</code>.
	 *
	 * <p>The metadata annotation takes the form of [EventHandler] in its simplest form. The name of the
	 * event will then be deducted from the method name. For instance, if you have an event called
	 * "saveUser", the handler is supposed to have the same name, or the same name with "Handler"
	 * attached to it. So "saveUser" and "saveUserHandler" are both valid handler names.</p>
	 *
	 * <p>If the name of the event and the event handler are different, or for clarity reasons, you can
	 * specify the event name via the "name" argument on the metadata. For example [EventHandler(name="saveUser")]
	 * is a valid form. You can also leave out the key of the name argument and just type [EventHandler("saveUser")].</p>
	 *
	 * <p>By default, an event handler function is expected to have a single argument of type Event (or any subclass).
	 * However if the event argument has additional properties, you can specify these properties directly as
	 * arguments of the handler function. For example if you have a <code>UserEvent</code> class with a property "user" of type
	 * User, the handler signature can look like this: <code>function saveUser(user:User):void</code></p>
	 *
	 * <p>If the custom event class has multiple properties of the same type, for example a "userA" and "userB" property
	 * both of type User, Spring ActionScript will not be able to figure out what properties correspond to the
	 * arguments of the handler function. In that case you need to specify the name of the properties in the
	 * metadata. e.g. [EventHandler(properties="userA, userB")]</p>
	 *
	 * <p>If the event handler is for a specific event class, add the fully qualified classname to the metadata like this:<br/>
	 * [EventHandler(clazz="com.classes.events.MyEventClass")].</p>
	 *
	 * <p>To determine if the event listener will be added using a weak reference, set the <code>useWeakReference</code> property like this:<br/>
	 * [EventHandler(clazz="com.classes.events.MyEventClass",useWeakReference="true")]
	 * </p>
	 *
	 * <p>To subscribe the event listener for a specific topic or topics, use this extra argument:<br/>
	 * [EventHandler(clazz="com.classes.events.MyEventClass",topics="topic1,topic2")]</p>
	 *
	 * <p>These metadata annotations can be stacked, so this is also valid:</p>
	 * <pre>
	 * [EventHandler(clazz="com.classes.events.MyEventClass1")]
	 * [EventHandler(clazz="com.classes.events.MyEventClass2",topics="topic1")]
	 * </pre>
	 *
	 * <p>Finally, to use the <code>EventHandlerMetaDataPostProcessor</code> in an application, add an object definition
	 * to the XML configuration like this:
	 * <pre>
	 * &lt;object id="eventhandlerProcessor" class="org.springextensions.actionscript.ioc.factory.config.EventHandlerMetaDataPostProcessor"/&gt;
	 * </pre>
	 * </p>
	 * <p>This way the processor will be automatically registered with the application context.</p>
	 * @see org.springextensions.actionscript.core.event.EventBus EventBus
	 * @author Christophe Herreman
	 * @docref the_eventbus.html#eventbus_event_handling_using_metadata_annotations
	 */
	public class EventHandlerMetadataProcessor extends AbstractEventBusMetadataProcessor implements IDisposable {

		// --------------------------------------------------------------------
		//
		// Public Static Constants
		//
		// --------------------------------------------------------------------

		/** The EventHandler metadata */
		private static const EVENT_HANDLER_METADATA:String = "EventHandler";

		/** The suffix optionally used in the name of an event handler. Complies to the Flex coding conventions. */
		private static const HANDLER_SUFFIX:String = "Handler";

		/** The "properties" property of the EventHandler metadata */
		private static const PROPERTIES_KEY:String = "properties";

		/** The "clazz" property of the EventHandler metadata */
		private static const CLASS_KEY:String = "clazz";

		private static const USEWEAK_KEY:String = "useWeakReference";

		private static const TRUE_VALUE:String = "true";
		private static const COMMA:String = ",";

		// --------------------------------------------------------------------
		//
		// Private Static Variables
		//
		// --------------------------------------------------------------------

		private static var logger:ILogger = getLogger(EventHandlerMetadataProcessor);

		// --------------------------------------------------------------------
		//
		// Private Variables
		//
		// --------------------------------------------------------------------

		private var _proxies:Dictionary;

		// --------------------------------------------------------------------
		//
		// Constructor
		//
		// --------------------------------------------------------------------

		/**
		 * Creates a new <code>EventHandlerMetaDataPostProcessor</code> instance.
		 */
		public function EventHandlerMetadataProcessor() {
			super(false, [EVENT_HANDLER_METADATA]);
			_proxies = new Dictionary(true);
		}

		// --------------------------------------------------------------------
		//
		// Public Properties
		//
		// --------------------------------------------------------------------

		// ----------------------------
		// eventBus
		// ----------------------------

		/**
		 * @inheritDoc
		 */
		public function get eventBus():IEventBus {
			return objFactory.eventBus;
		}

		// ----------------------------
		// isDisposed
		// ----------------------------

		private var _isDisposed:Boolean = false;

		public function get isDisposed():Boolean {
			return _isDisposed;
		}

		// --------------------------------------------------------------------
		//
		// Public Methods
		//
		// --------------------------------------------------------------------

		override public function process(instance:Object, container:IMetadataContainer, name:String, objectName:String):void {
			var method:Method = (container as Method);

			if (method == null) {
				return;
			}

			var metaDatas:Array = method.getMetadata(EVENT_HANDLER_METADATA);
			for each (var metaData:Metadata in metaDatas) {
				processMetaData(instance, method, metaData);
			}
		}

		public function removeEventListener(eventName:String, handler:Function = null):void {
			for (var proxy:* in _proxies) {
				var key:* = _proxies[proxy];
				if (key is String) {
					var name:String = String(key);
					var m:MethodInvoker = MethodInvoker(proxy);
					if ((name == eventName) && ((handler == null) || (handler === m.target[m.method]))) {
						eventBus.removeEventListenerProxy(name, m);
					}
				}
			}
		}

		public function removeEventClassListener(eventClass:Class, handler:Function = null):void {
			for (var proxy:* in _proxies) {
				var key:* = _proxies[proxy];
				if (key is Class) {
					var cls:Class = Class(key);
					var m:MethodInvoker = MethodInvoker(proxy);
					if ((cls === eventClass) && ((handler == null) || (handler === m.target[m.method]))) {
						eventBus.removeEventClassListenerProxy(cls, m);
					}
				}
			}
		}

		/**
		 * Loops through all the event handlers that have been previously added by the
		 * current <code>EventHandlerMetaDataPostProcessor</code>, removes them and
		 * clears and nulls the internal cache.
		 */
		public function dispose():void {
			if (!_isDisposed) {
				for (var proxy:* in _proxies) {
					var key:* = _proxies[proxy];
					if (key is Class) {
						eventBus.removeEventClassListenerProxy(Class(key), MethodInvoker(proxy));
					} else if (key is String) {
						eventBus.removeEventListenerProxy(String(key), MethodInvoker(proxy));
					}
					delete _proxies[proxy];
				}
				_proxies = null;
				_isDisposed = true;
			}
		}

		// --------------------------------------------------------------------
		//
		// Protected Methods
		//
		// --------------------------------------------------------------------

		protected function processMetaData(object:Object, method:Method, metaData:Metadata):void {
			var className:String = getEventClassName(metaData);
			var properties:Array = getProperties(metaData);
			var topics:Array = getTopics(metaData, object);
			topics = (topics.length > 0) ? topics : null;
			var useWeak:Boolean = getUseWeak(metaData);
			var proxy:EventHandlerProxy = new EventHandlerProxy(object, method, properties);
			var topic:Object;
			proxy.applicationDomain = objFactory.applicationDomain;

			if (className == null) {
				var eventName:String = getEventName(method, metaData);
				_proxies[proxy] = eventName;
				if (topics == null) {
					eventBus.addEventListenerProxy(eventName, proxy, useWeak);
					logger.debug("Added event handler for '{0}' on the EventBus", [eventName]);
				} else {
					for each (topic in topics) {
						eventBus.addEventListenerProxy(eventName, proxy, useWeak, topic);
						logger.debug("Added event handler for '{0}' on the EventBus for topic {1}", [eventName, topic]);
					}
				}
			} else {
				var cls:Class = ClassUtils.forName(className, objFactory.applicationDomain);
				_proxies[proxy] = cls;
				if (topics == null) {
					eventBus.addEventClassListenerProxy(cls, proxy, useWeak);
					logger.debug("Added event class handler for '{0}' on the EventBus", [className]);
				} else {
					for each (topic in topics) {
						eventBus.addEventClassListenerProxy(cls, proxy, useWeak, topic);
						logger.debug("Added event class handler for '{0}' on the EventBus for topic {1}", [eventName, topic]);
					}
				}
			}
		}

		protected function getEventClassName(metaData:Metadata):String {
			var result:String = null;

			if (metaData.hasArgumentWithKey(CLASS_KEY)) {
				result = metaData.getArgument(CLASS_KEY).value;
			}

			return result;
		}

		/**
		 * Returns the name of the event to listen to.
		 *
		 * @param method
		 * @param metaData
		 * @return the name of the event
		 */
		protected function getEventName(method:Method, metaData:Metadata):String {
			if (metaData.arguments.length == 0) {
				return getEventNameFromMethod(method);
			}
			return getEventNameFromMetaData(metaData);
		}

		/**
		 * Returns the event name based on the given method. We assume that the
		 * name of the method corresponds to a event, or to the name of the event followed by "Handler".
		 *
		 * @param method
		 */
		protected function getEventNameFromMethod(method:Method):String {
			var result:String = method.name;

			if (StringUtils.endsWith(result, HANDLER_SUFFIX)) {
				result = result.substr(0, result.length - HANDLER_SUFFIX.length);
			}

			return result;
		}

		/**
		 * Returns the name of the event from the given metadata. This will either be the value
		 * of the argument with the "name" key, or the value of the argument without a key.
		 */
		protected function getEventNameFromMetaData(metaData:Metadata):String {
			var result:String;

			if (metaData.hasArgumentWithKey(NAME_KEY)) {
				result = metaData.getArgument(NAME_KEY).value;
			} else {
				// no explicit name defined, look for the default argument
				var args:Array = metaData.arguments;
				for each (var arg:MetadataArgument in args) {
					if (!arg.key) {
						result = arg.value;
					}
				}
			}

			return result;
		}

		protected function getProperties(metaData:Metadata):Array {
			if (metaData.hasArgumentWithKey(PROPERTIES_KEY)) {
				var propertiesValue:String = metaData.getArgument(PROPERTIES_KEY).value;
				var result:Array = propertiesValue.split(COMMA);
				result.forEach(trim);
				return result;
			}
			return null;
		}

		protected function getUseWeak(metaData:Metadata):Boolean {
			if (metaData.hasArgumentWithKey(USEWEAK_KEY)) {
				var weakValue:String = metaData.getArgument(USEWEAK_KEY).value.toLowerCase();
				return (weakValue == TRUE_VALUE);
			}
			return false;
		}

	}
}